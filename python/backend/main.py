"""FastAPI app + routes (§5). Runs as a single local process bound to
127.0.0.1 — no network exposure, no database, no auth (single-user local
desktop tool).
"""

import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, PlainTextResponse

from . import manifest, ps_bridge, reports
from .__version__ import __version__
from .models import (
    ApplyItemResult,
    ApplyRequest,
    ApplyRunResult,
    CatalogItem,
    PCSpecs,
    ScanRequest,
    ScanResult,
    SystemInventory,
    ToolMeta,
    UndoItemResult,
)

TOOL_META = {
    "fps": ToolMeta(
        Key="fps",
        Name="FPS Optimizer",
        Tag="FOR GAMING RIGS",
        Desc="Deep gaming optimization: telemetry & background-contention elimination, "
        "service debloat, NIC tuning, and aggressive security trade-offs.",
        Meta="v0.3 · 54 checks · apply is reversible",
    ),
    "startup": ToolMeta(
        Key="startup",
        Name="Startup Optimizer",
        Tag="FOR EVERYDAY PCs",
        Desc="Lists every app, logon task, and Windows extra that launches itself at logon "
        "— uncheck the keepers, clear the rest.",
        Meta="v0.1 · dynamic scan · apply is reversible",
    ),
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.locks = {"fps": threading.Lock(), "startup": threading.Lock()}
    app.state.scan_pc_lock = threading.Lock()
    app.state.last_scan: dict[str, list[ScanResult]] = {}
    app.state.system_scan: SystemInventory | None = None
    app.state.ps_host_error: str | None = None
    app.state.pc_specs: PCSpecs | None = None

    # Only resolve the PS host here (shutil.which — instant, no subprocess).
    # No scan of any kind runs until the user presses a Scan button: not the
    # PC-specs/system scan, not a tool's catalog scan. Startup used to run
    # the full system scan synchronously, which blocked uvicorn from
    # accepting connections for as long as that scan took (installed-software
    # enumeration especially) — the webview window would sit unresponsive
    # with nothing to show for it in the meantime.
    try:
        ps_bridge.resolve_ps_exe()
    except ps_bridge.PSHostNotFoundError as e:
        # Don't crash the process — the frontend needs the app alive to show
        # a startup-health banner for this, same posture as the WPF hub's
        # MessageBox for the same condition (§5.5).
        app.state.ps_host_error = str(e)

    yield


app = FastAPI(title="PcTuner-Open-Source", lifespan=lifespan)


def _require_tool(tool: str) -> None:
    if tool not in TOOL_META:
        raise HTTPException(404, f"unknown tool '{tool}'")


def _catalog_by_id(tool: str) -> dict[str, CatalogItem]:
    items = manifest.load_catalog(tool)
    return {item.Id: item for item in items}


@app.get("/api/health")
def health():
    return {"ok": app.state.ps_host_error is None, "ps_host_error": app.state.ps_host_error}


@app.get("/api/version")
def get_version():
    return {"version": __version__}


@app.get("/api/tools")
def get_tools():
    return {"specs": app.state.pc_specs, "tools": list(TOOL_META.values())}


@app.get("/api/{tool}/catalog", response_model=list[CatalogItem])
def get_catalog(tool: str):
    _require_tool(tool)
    return manifest.load_catalog(tool)


@app.post("/api/{tool}/scan", response_model=list[ScanResult])
def post_scan(tool: str, req: ScanRequest):
    _require_tool(tool)
    lock = app.state.locks[tool]
    if not lock.acquire(blocking=False):
        raise HTTPException(409, f"a scan or apply is already in progress for '{tool}'")
    try:
        items = manifest.load_catalog(tool)
        results = ps_bridge.scan_catalog(items, set(req.checked))
        app.state.last_scan[tool] = results
        reports.write_scan_report(tool, app.state.pc_specs, results)
        return results
    finally:
        lock.release()


@app.get("/api/{tool}/report/latest")
def get_latest_report(tool: str):
    _require_tool(tool)
    report = reports.latest_scan_report(tool)
    if report is None:
        raise HTTPException(404, f"no report yet for '{tool}'")
    return report


@app.get("/api/{tool}/report/latest.md")
def get_latest_report_markdown(tool: str):
    _require_tool(tool)
    markdown = reports.latest_scan_report_markdown(tool)
    if markdown is None:
        raise HTTPException(404, f"no report yet for '{tool}'")
    return PlainTextResponse(markdown, media_type="text/markdown")


@app.post("/api/{tool}/apply", response_model=ApplyRunResult)
def post_apply(tool: str, req: ApplyRequest):
    _require_tool(tool)
    lock = app.state.locks[tool]
    if not lock.acquire(blocking=False):
        raise HTTPException(409, f"a scan or apply is already in progress for '{tool}'")
    try:
        last_scan = app.state.last_scan.get(tool)
        if last_scan is None:
            raise HTTPException(400, "scan before applying — no recent scan result for this tool")

        # Never trust eligibility from the client alone (§8.5): only ids
        # both checked AND scanned PENDING on the most recent scan.
        eligible_ids = {r.Id for r in last_scan if r.Status == "PENDING"}
        checked_ids = [i for i in req.checked if i in eligible_ids]
        if not checked_ids:
            raise HTTPException(400, "none of the requested ids are apply-eligible (checked + PENDING)")

        try:
            game = ps_bridge.check_game_running()
        except ps_bridge.PSBridgeError as e:
            raise HTTPException(500, f"game pre-flight check failed: {e.message}") from e
        if game.get("GameRunning"):
            # Whole-run pre-flight refusal, not per-item skip (§8.5).
            raise HTTPException(409, f"a game is running ({game.get('Names')}) — apply refused")

        # The confirm modal tells the user "a System Restore Point will be
        # created first" — the result used to be caught and discarded here,
        # so that promise could silently not happen with no indication to
        # anyone. It's still a coarse safety net on top of the undo log
        # (§8.5), so a failure here never blocks the apply itself — it's
        # just no longer a secret.
        restore_point_ok = True
        restore_point_note: str | None = None
        try:
            rp = ps_bridge.create_restore_point(f"PCTuner apply — {TOOL_META[tool].Name}")
            restore_point_ok = bool(rp.get("Success"))
            restore_point_note = rp.get("Note")
        except ps_bridge.PSBridgeError as e:
            restore_point_ok = False
            restore_point_note = e.message

        items_by_id = _catalog_by_id(tool)
        undo_log = reports.UndoLog(tool)
        results: list[ApplyItemResult] = []
        for result in ps_bridge.apply_sequential(items_by_id, checked_ids):
            undo_log.record(result, items_by_id[result.Id])
            results.append(result)

        reports.write_apply_report(tool, results)
        # Invalidate rather than trust the scan that got us here: it no
        # longer reflects reality the instant any item actually changed.
        # Without this, two POST /apply calls in a row with the same body
        # both pass the "checked + PENDING" re-validation using the SAME
        # stale scan, and the second apply's undo log ends up recording the
        # already-optimized value as "PreviousValue" — Undo would then
        # "restore" straight back to the optimized state. The frontend
        # already re-scans after every apply, which masks this in normal
        # use, but the server-side check needs to be correct on its own.
        app.state.last_scan.pop(tool, None)
        return ApplyRunResult(
            Results=results, RestorePointOk=restore_point_ok, RestorePointNote=restore_point_note
        )
    finally:
        lock.release()


@app.get("/api/{tool}/undo/available")
def get_undo_available(tool: str):
    _require_tool(tool)
    age = reports.undo_log_age_seconds(tool)
    return {"available": age is not None, "ageSeconds": age}


@app.post("/api/{tool}/undo", response_model=list[UndoItemResult])
def post_undo(tool: str):
    _require_tool(tool)
    lock = app.state.locks[tool]
    if not lock.acquire(blocking=False):
        raise HTTPException(409, f"a scan or apply is already in progress for '{tool}'")
    try:
        undo_records = reports.latest_undo_log(tool)
        if not undo_records:
            raise HTTPException(404, f"no apply run to undo for '{tool}'")
        results = list(ps_bridge.undo_sequential(undo_records))
        # Only retire on a fully clean run — a partial failure should leave
        # the log in place so the user can retry via the same button rather
        # than losing the ability to finish undoing what's left.
        if results and all(r.Success for r in results):
            reports.retire_undo_log(tool)
        # Same reasoning as post_apply: the most recent scan no longer
        # reflects reality once anything actually got reverted.
        app.state.last_scan.pop(tool, None)
        return results
    finally:
        lock.release()


@app.post("/api/scan-pc", response_model=SystemInventory)
def post_scan_pc():
    # Every other long-running route (scan/apply/undo) guards against
    # concurrent calls racing on shared state -- this one didn't, so two
    # rapid "Scan PC" clicks could race on shared\cache\SystemScan.json.
    if not app.state.scan_pc_lock.acquire(blocking=False):
        raise HTTPException(409, "a PC scan is already in progress")
    try:
        scan = ps_bridge.run_system_scan()
        inventory = SystemInventory(**scan)
        app.state.system_scan = inventory
        app.state.pc_specs = inventory.Specs
        return inventory
    finally:
        app.state.scan_pc_lock.release()


@app.get("/api/scan-pc")
def get_scan_pc():
    return app.state.system_scan or JSONResponse(None)
