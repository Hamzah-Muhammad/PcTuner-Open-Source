import pytest
from fastapi.testclient import TestClient

from backend import main, manifest, ps_bridge, reports
from backend.models import ApplyItemResult, ScanResult, UndoItemResult


@pytest.fixture
def client(monkeypatch, tmp_path, fake_catalog, fake_system_scan):
    monkeypatch.setattr(ps_bridge, "resolve_ps_exe", lambda: "C:\\fake\\pwsh.exe")
    monkeypatch.setattr(ps_bridge, "run_system_scan", lambda: fake_system_scan)
    monkeypatch.setattr(manifest, "load_catalog", lambda tool: fake_catalog)
    monkeypatch.setattr(main.reports.paths, "logs_dir", lambda tool: tmp_path / tool)

    with TestClient(main.app) as c:
        yield c


def test_health_ok(client):
    assert client.get("/api/health").json() == {"ok": True, "ps_host_error": None}


def test_version_matches_single_source_of_truth(client):
    from backend.__version__ import __version__

    assert client.get("/api/version").json() == {"version": __version__}


def test_get_tools_returns_no_specs_before_any_scan(client):
    # No scan of any kind runs automatically at startup (user directive) —
    # specs stay null until /api/scan-pc is explicitly triggered.
    body = client.get("/api/tools").json()
    assert body["specs"] is None
    assert {t["Key"] for t in body["tools"]} == {"fps", "startup"}


def test_scan_pc_populates_tools_specs(client):
    client.post("/api/scan-pc")
    body = client.get("/api/tools").json()
    assert body["specs"]["CPU"] == "Fake CPU"


def test_get_catalog_unknown_tool_404(client):
    assert client.get("/api/bogus/catalog").status_code == 404


def test_get_catalog_returns_fake_items(client):
    body = client.get("/api/fps/catalog").json()
    assert [i["Id"] for i in body] == ["A.1", "A.2"]


def test_scan_writes_report_and_caches_last_scan(client, monkeypatch, tmp_path):
    scanned = [
        ScanResult(Id="A.1", Name="Item A", Status="PENDING", Current="off", Target="on"),
        ScanResult(Id="A.2", Name="Item B", Status="APPLIED", Current="on", Target="on"),
    ]
    monkeypatch.setattr(ps_bridge, "scan_catalog", lambda items, checked: scanned)

    resp = client.post("/api/fps/scan", json={"checked": ["A.1", "A.2"]})
    assert resp.status_code == 200
    assert [r["Status"] for r in resp.json()] == ["PENDING", "APPLIED"]
    assert main.app.state.last_scan["fps"] == scanned
    assert list((tmp_path / "fps").glob("DryRun_*.md"))


def test_report_latest_404_before_any_scan(client):
    assert client.get("/api/fps/report/latest").status_code == 404


def test_report_latest_after_scan(client, monkeypatch):
    scanned = [ScanResult(Id="A.1", Name="Item A", Status="PENDING", Current="off", Target="on")]
    monkeypatch.setattr(ps_bridge, "scan_catalog", lambda items, checked: scanned)
    client.post("/api/fps/scan", json={"checked": ["A.1"]})

    body = client.get("/api/fps/report/latest").json()
    assert body["results"][0]["Id"] == "A.1"


def test_apply_requires_prior_scan(client):
    resp = client.post("/api/fps/apply", json={"checked": ["A.1"]})
    assert resp.status_code == 400
    assert "scan before applying" in resp.json()["detail"]


def test_apply_filters_to_checked_and_pending_only(client, monkeypatch):
    scanned = [
        ScanResult(Id="A.1", Name="Item A", Status="PENDING", Current="off", Target="on"),
        ScanResult(Id="A.2", Name="Item B", Status="APPLIED", Current="on", Target="on"),
    ]
    monkeypatch.setattr(ps_bridge, "scan_catalog", lambda items, checked: scanned)
    client.post("/api/fps/scan", json={"checked": ["A.1", "A.2"]})

    monkeypatch.setattr(ps_bridge, "check_game_running", lambda: {"GameRunning": False, "Names": None})
    monkeypatch.setattr(ps_bridge, "create_restore_point", lambda desc: {"Success": True, "Note": None})

    captured = {}

    def fake_apply_sequential(items_by_id, checked_ids):
        captured["checked_ids"] = checked_ids
        yield ApplyItemResult(Id="A.1", Success=True, PreviouslyExisted=True, PreviousValue=1)

    monkeypatch.setattr(ps_bridge, "apply_sequential", fake_apply_sequential)

    # A.2 is APPLIED (not PENDING) — must be filtered out server-side even
    # though the client checked it, per §8.5's "never trust client alone".
    resp = client.post("/api/fps/apply", json={"checked": ["A.1", "A.2"]})
    assert resp.status_code == 200
    assert captured["checked_ids"] == ["A.1"]


def test_apply_refuses_when_game_running(client, monkeypatch):
    scanned = [ScanResult(Id="A.1", Name="Item A", Status="PENDING", Current="off", Target="on")]
    monkeypatch.setattr(ps_bridge, "scan_catalog", lambda items, checked: scanned)
    client.post("/api/fps/scan", json={"checked": ["A.1"]})

    monkeypatch.setattr(ps_bridge, "check_game_running", lambda: {"GameRunning": True, "Names": "cs2"})

    resp = client.post("/api/fps/apply", json={"checked": ["A.1"]})
    assert resp.status_code == 409
    assert "cs2" in resp.json()["detail"]


def test_apply_writes_undo_log_only_for_successful_items(client, monkeypatch, tmp_path):
    scanned = [
        ScanResult(Id="A.1", Name="Item A", Status="PENDING", Current="off", Target="on"),
        ScanResult(Id="A.2", Name="Item B", Status="PENDING", Current="off", Target="on"),
    ]
    monkeypatch.setattr(ps_bridge, "scan_catalog", lambda items, checked: scanned)
    client.post("/api/fps/scan", json={"checked": ["A.1", "A.2"]})

    monkeypatch.setattr(ps_bridge, "check_game_running", lambda: {"GameRunning": False, "Names": None})
    monkeypatch.setattr(ps_bridge, "create_restore_point", lambda desc: {"Success": True, "Note": None})

    def fake_apply_sequential(items_by_id, checked_ids):
        yield ApplyItemResult(Id="A.1", Success=True, PreviouslyExisted=True, PreviousValue=1)
        yield ApplyItemResult(Id="A.2", Success=False, Error="denied")

    monkeypatch.setattr(ps_bridge, "apply_sequential", fake_apply_sequential)

    client.post("/api/fps/apply", json={"checked": ["A.1", "A.2"]})

    undo_files = list((tmp_path / "fps").glob("UndoLog_*.json"))
    assert len(undo_files) == 1
    import json as jsonlib

    records = jsonlib.loads(undo_files[0].read_text())
    assert [r["Id"] for r in records] == ["A.1"]


def test_undo_available_false_before_any_apply(client):
    assert client.get("/api/fps/undo/available").json() == {"available": False}


def test_undo_available_true_after_apply(client, monkeypatch):
    monkeypatch.setattr(reports, "latest_undo_log", lambda tool: [{"Id": "A.1"}])
    assert client.get("/api/fps/undo/available").json() == {"available": True}


def test_undo_no_prior_apply_404(client):
    assert client.post("/api/fps/undo").status_code == 404


def test_undo_uses_latest_log(client, monkeypatch):
    undo_record = {
        "Id": "A.1",
        "PreviouslyExisted": True,
        "PreviousValue": 1,
        "ScriptPath": "C:\\fake\\A.ps1",
        "ScriptArgs": {},
    }
    monkeypatch.setattr(reports, "latest_undo_log", lambda tool: [undo_record])
    monkeypatch.setattr(
        ps_bridge,
        "undo_sequential",
        lambda records: iter([UndoItemResult(Id="A.1", Success=True)]),
    )
    resp = client.post("/api/fps/undo")
    assert resp.status_code == 200
    assert resp.json()[0]["Success"] is True


def test_scan_pc_post_then_get(client):
    posted = client.post("/api/scan-pc").json()
    assert posted["Specs"]["CPU"] == "Fake CPU"
    got = client.get("/api/scan-pc").json()
    assert got["Specs"]["CPU"] == "Fake CPU"


def test_scan_pc_get_before_post_is_null(client):
    assert client.get("/api/scan-pc").json() is None
