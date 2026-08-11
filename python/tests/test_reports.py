import time

from backend import reports


def test_undo_log_age_seconds_none_when_no_log(monkeypatch, tmp_path):
    monkeypatch.setattr(reports.paths, "logs_dir", lambda tool: tmp_path / tool)
    assert reports.undo_log_age_seconds("fps") is None


def test_undo_log_age_seconds_reflects_real_file_age(monkeypatch, tmp_path):
    log_dir = tmp_path / "fps"
    log_dir.mkdir()
    log_file = log_dir / "UndoLog_20260101_000000.json"
    log_file.write_text("[]", encoding="utf-8")
    old_mtime = time.time() - 120
    import os

    os.utime(log_file, (old_mtime, old_mtime))

    monkeypatch.setattr(reports.paths, "logs_dir", lambda tool: tmp_path / tool)
    age = reports.undo_log_age_seconds("fps")
    assert age is not None
    assert 115 <= age <= 130


def test_retire_undo_log_renames_off_the_glob(monkeypatch, tmp_path):
    log_dir = tmp_path / "fps"
    log_dir.mkdir()
    log_file = log_dir / "UndoLog_20260101_000000.json"
    log_file.write_text('[{"Id": "A.1"}]', encoding="utf-8")

    monkeypatch.setattr(reports.paths, "logs_dir", lambda tool: tmp_path / tool)
    reports.retire_undo_log("fps")

    assert not list(log_dir.glob("UndoLog_*.json"))
    consumed = list(log_dir.glob("ConsumedUndoLog_*.json"))
    assert len(consumed) == 1
    # Content is preserved verbatim -- this is a rename, not a rewrite.
    assert consumed[0].read_text(encoding="utf-8") == '[{"Id": "A.1"}]'
    # And it no longer counts as an active undo log.
    assert reports.latest_undo_log("fps") is None


def test_retire_undo_log_is_a_safe_no_op_when_nothing_to_retire(monkeypatch, tmp_path):
    monkeypatch.setattr(reports.paths, "logs_dir", lambda tool: tmp_path / tool)
    reports.retire_undo_log("fps")  # must not raise
