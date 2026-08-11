import json
import subprocess

import pytest

from backend import ps_bridge
from backend.models import CatalogItem


class FakeProc:
    def __init__(self, returncode=0, stdout="", stderr=""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def _item(script_path="C:\\fake\\Item.ps1", **kw):
    defaults = dict(
        Id="1.1",
        Level=1,
        Module="Mod",
        Name="Name",
        Desc="desc",
        Target="target",
        DefaultChecked=True,
        ScriptPath=script_path,
        ScriptArgs={},
    )
    defaults.update(kw)
    return CatalogItem(**defaults)


@pytest.fixture(autouse=True)
def fake_ps_exe(monkeypatch):
    monkeypatch.setattr(ps_bridge, "_ps_exe", "C:\\fake\\pwsh.exe")


def test_resolve_ps_exe_found(monkeypatch):
    monkeypatch.setattr(ps_bridge, "_ps_exe", None)
    monkeypatch.setattr(
        ps_bridge.shutil, "which", lambda name: "C:\\real\\pwsh.exe" if name == "pwsh" else None
    )
    assert ps_bridge.resolve_ps_exe() == "C:\\real\\pwsh.exe"


def test_resolve_ps_exe_missing_raises(monkeypatch):
    monkeypatch.setattr(ps_bridge, "_ps_exe", None)
    monkeypatch.setattr(ps_bridge.shutil, "which", lambda name: None)
    with pytest.raises(ps_bridge.PSHostNotFoundError):
        ps_bridge.resolve_ps_exe()


def test_change_script_args_uses_colon_syntax_for_leading_dash_values(monkeypatch):
    """A real registry ValueName can start with '-' (e.g. "-Undo"). Passed as
    two separate argv tokens ("-ValueName", "-Undo"), PowerShell's own
    parameter binder reads the second token as the START OF A NEW PARAMETER
    rather than this one's value, and the script dies with "Missing an
    argument for parameter 'ValueName'". The -Key:value colon form is a
    single token and sidesteps this regardless of what the value looks like."""
    captured = {}

    def fake_run(cmd, **kw):
        captured["cmd"] = cmd
        return FakeProc(0, json.dumps({"Id": "1.1", "Mode": "Check", "Status": "APPLIED", "Current": "ok"}))

    monkeypatch.setattr(subprocess, "run", fake_run)
    item = _item(ScriptArgs={"ValueName": "-Undo"})
    ps_bridge.run_change_item(item, "Check")

    assert "-ValueName:-Undo" in captured["cmd"]
    assert "-ValueName" not in captured["cmd"]  # would be the broken two-token form


def test_run_change_item_check_success(monkeypatch):
    payload = {"Id": "1.1", "Mode": "Check", "Status": "PENDING", "Current": "AllowTelemetry = 3"}
    monkeypatch.setattr(subprocess, "run", lambda *a, **kw: FakeProc(0, json.dumps(payload)))
    result = ps_bridge.run_change_item(_item(), "Check")
    assert result == payload


def test_run_change_item_nonzero_exit_raises(monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda *a, **kw: FakeProc(1, "", "boom"))
    with pytest.raises(ps_bridge.PSBridgeError) as exc:
        ps_bridge.run_change_item(_item(), "Check")
    assert exc.value.item_id == "1.1"
    assert "boom" in exc.value.message


def test_run_change_item_error_payload_with_nonzero_exit(monkeypatch):
    payload = {"Id": "1.1", "Error": "registry access denied"}
    monkeypatch.setattr(subprocess, "run", lambda *a, **kw: FakeProc(1, json.dumps(payload), ""))
    with pytest.raises(ps_bridge.PSBridgeError) as exc:
        ps_bridge.run_change_item(_item(), "Check")
    assert exc.value.message == "registry access denied"


def test_run_change_item_malformed_json_raises(monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda *a, **kw: FakeProc(0, "{not json"))
    with pytest.raises(ps_bridge.PSBridgeError):
        ps_bridge.run_change_item(_item(), "Check")


def test_run_change_item_timeout_raises(monkeypatch):
    def raise_timeout(*a, **kw):
        raise subprocess.TimeoutExpired(cmd="pwsh", timeout=15)

    monkeypatch.setattr(subprocess, "run", raise_timeout)
    with pytest.raises(ps_bridge.PSBridgeError) as exc:
        ps_bridge.run_change_item(_item(), "Check")
    assert "timed out" in exc.value.message


def test_run_change_item_placeholder_check_is_synthetic_no_subprocess(monkeypatch):
    def fail(*a, **kw):
        raise AssertionError("subprocess.run should never be called for a placeholder item")

    monkeypatch.setattr(subprocess, "run", fail)
    result = ps_bridge.run_change_item(_item(script_path=None), "Check")
    assert result == {"Id": "1.1", "Mode": "Check", "Status": "APPLIED", "Current": "clean"}


def test_run_change_item_placeholder_apply_raises(monkeypatch):
    with pytest.raises(ps_bridge.PSBridgeError):
        ps_bridge.run_change_item(_item(script_path=None), "Apply")


def test_scan_catalog_skips_unchecked_without_subprocess(monkeypatch):
    def fail(*a, **kw):
        raise AssertionError("unchecked items must never spawn a subprocess")

    monkeypatch.setattr(subprocess, "run", fail)
    items = [_item(Id="1.1"), _item(Id="1.2")]
    results = ps_bridge.scan_catalog(items, checked_ids=set())
    assert {r.Status for r in results} == {"SKIPPED"}


def test_scan_catalog_survives_malformed_but_valid_json_from_one_item(monkeypatch):
    """A script that exits 0 with valid JSON missing an expected key (or
    shaped as a list, e.g. the exact bug class H1 fixed elsewhere) used to
    raise an uncaught KeyError/TypeError here, which took the ENTIRE scan
    down -- losing every other item's already-good result along with it.
    One bad item must degrade to its own ERROR row instead."""

    def fake_run(cmd, **kw):
        script = cmd[-2]
        if "good.ps1" in script:
            return FakeProc(0, json.dumps({"Id": "good", "Status": "APPLIED", "Current": "ok"}))
        # Valid JSON, exit 0, but missing "Status"/"Current" entirely.
        return FakeProc(0, json.dumps({"Id": "bad"}))

    monkeypatch.setattr(subprocess, "run", fake_run)
    items = [
        _item(Id="good", script_path="C:\\fake\\good.ps1"),
        _item(Id="bad", script_path="C:\\fake\\bad.ps1"),
    ]
    results = {r.Id: r for r in ps_bridge.scan_catalog(items, checked_ids={"good", "bad"})}
    assert results["good"].Status == "APPLIED"
    assert results["bad"].Status == "ERROR"
    assert "malformed" in results["bad"].Current


def test_scan_catalog_maps_status_and_errors(monkeypatch):
    def fake_run(cmd, **kw):
        # cmd is [..., "-File", script, "-Check"] — script is second-to-last.
        if "A.ps1" in cmd[-2]:
            return FakeProc(0, json.dumps({"Id": "A", "Status": "APPLIED", "Current": "ok"}))
        return FakeProc(1, "", "explosion")

    monkeypatch.setattr(subprocess, "run", fake_run)
    items = [
        _item(Id="A", script_path="C:\\fake\\A.ps1"),
        _item(Id="B", script_path="C:\\fake\\B.ps1"),
    ]
    results = {r.Id: r for r in ps_bridge.scan_catalog(items, checked_ids={"A", "B"})}
    assert results["A"].Status == "APPLIED"
    assert results["B"].Status == "ERROR"
    assert "explosion" in results["B"].Current


def test_scan_catalog_preserves_input_order(monkeypatch):
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda cmd, **kw: FakeProc(0, json.dumps({"Id": "x", "Status": "APPLIED", "Current": "ok"})),
    )
    items = [_item(Id=f"{n}") for n in ("3", "1", "2")]
    results = ps_bridge.scan_catalog(items, checked_ids={"1", "2", "3"})
    assert [r.Id for r in results] == ["3", "1", "2"]


def test_apply_sequential_yields_results_in_order(monkeypatch):
    def fake_run(cmd, **kw):
        script = cmd[-2]
        applied_id = "A" if "A.ps1" in script else "B"
        return FakeProc(
            0,
            json.dumps(
                {
                    "Id": applied_id,
                    "Mode": "Apply",
                    "Success": True,
                    "PreviouslyExisted": True,
                    "PreviousValue": 3,
                    "Note": None,
                }
            ),
        )

    monkeypatch.setattr(subprocess, "run", fake_run)
    items_by_id = {
        "A": _item(Id="A", script_path="C:\\fake\\A.ps1"),
        "B": _item(Id="B", script_path="C:\\fake\\B.ps1"),
    }
    results = list(ps_bridge.apply_sequential(items_by_id, ["A", "B"]))
    assert [r.Id for r in results] == ["A", "B"]
    assert all(r.Success for r in results)


def test_apply_sequential_continues_after_one_item_errors(monkeypatch):
    def fake_run(cmd, **kw):
        script = cmd[-2]
        if "A.ps1" in script:
            return FakeProc(1, "", "denied")
        return FakeProc(
            0,
            json.dumps(
                {
                    "Id": "B",
                    "Mode": "Apply",
                    "Success": True,
                    "PreviouslyExisted": False,
                    "PreviousValue": None,
                    "Note": None,
                }
            ),
        )

    monkeypatch.setattr(subprocess, "run", fake_run)
    items_by_id = {
        "A": _item(Id="A", script_path="C:\\fake\\A.ps1"),
        "B": _item(Id="B", script_path="C:\\fake\\B.ps1"),
    }
    results = list(ps_bridge.apply_sequential(items_by_id, ["A", "B"]))
    assert results[0].Success is False
    assert results[1].Success is True


def test_undo_sequential_builds_previous_value_json(monkeypatch):
    captured = {}

    def fake_run(cmd, **kw):
        captured["cmd"] = cmd
        return FakeProc(0, json.dumps({"Id": "A", "Mode": "Undo", "Success": True, "Note": None}))

    monkeypatch.setattr(subprocess, "run", fake_run)
    records = [
        {
            "Id": "A",
            "PreviouslyExisted": True,
            "PreviousValue": 5,
            "ScriptPath": "C:\\fake\\A.ps1",
            "ScriptArgs": {},
        }
    ]
    results = list(ps_bridge.undo_sequential(records))
    assert results[0].Success is True
    prev_json_index = captured["cmd"].index("-PreviousValueJson") + 1
    assert json.loads(captured["cmd"][prev_json_index]) == {"PreviouslyExisted": True, "PreviousValue": 5}


def test_undo_sequential_uses_snapshotted_target_not_catalog_lookup(monkeypatch):
    """The whole point of C2's fix: Undo must act on the ScriptPath/ScriptArgs
    recorded at apply time, never on a freshly-reloaded catalog — proven here
    by never even constructing a catalog, let alone a stale/shifted one."""
    captured = {}

    def fake_run(cmd, **kw):
        captured["cmd"] = cmd
        return FakeProc(0, json.dumps({"Id": "R.abc123", "Mode": "Undo", "Success": True, "Note": None}))

    monkeypatch.setattr(subprocess, "run", fake_run)
    records = [
        {
            "Id": "R.abc123",
            "PreviouslyExisted": True,
            "PreviousValue": "some-old-command",
            "ScriptPath": "C:\\fake\\RunKeyEntry.ps1",
            "ScriptArgs": {"RegPath": "HKCU:\\Run", "ValueName": "LGHUB"},
        }
    ]
    results = list(ps_bridge.undo_sequential(records))
    assert results[0].Success is True
    # -Key:value as one token, not two -- see test_change_script_args_uses_colon_syntax
    # for why (a value starting with "-" breaks the two-token form).
    assert "-RegPath:HKCU:\\Run" in captured["cmd"]
    assert "-ValueName:LGHUB" in captured["cmd"]


def test_undo_sequential_missing_script_path_reports_failure():
    record = {"Id": "ghost", "PreviouslyExisted": True, "PreviousValue": 1}
    results = list(ps_bridge.undo_sequential([record]))
    assert results[0].Success is False
    assert "no script recorded" in results[0].Error


def test_check_game_running_parses_output(monkeypatch):
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda cmd, **kw: FakeProc(0, json.dumps({"GameRunning": True, "Names": "cs2"})),
    )
    result = ps_bridge.check_game_running()
    assert result == {"GameRunning": True, "Names": "cs2"}


def test_create_restore_point_nonfatal_shape(monkeypatch):
    monkeypatch.setattr(
        subprocess,
        "run",
        lambda cmd, **kw: FakeProc(0, json.dumps({"Success": False, "Note": "throttled"})),
    )
    result = ps_bridge.create_restore_point("test run")
    assert result == {"Success": False, "Note": "throttled"}
