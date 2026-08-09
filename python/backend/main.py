"""FastAPI app + routes (§5). Runs as a single local process bound to
127.0.0.1 — no network exposure, no database, no auth (single-user local
desktop tool).
"""

import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from . import manifest, ps_bridge, reports
from .__version__ import __version__
from .models import (
    ApplyItemResult,
    ApplyRequest,
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
        Meta="v0.3 · 54 checks · dry run",
    ),
    "startup": ToolMeta(
        Key="startup",
        Name="Startup Optimizer",
        Tag="FOR EVERYDAY PCs",
        Desc="Lists every app, logon task, and Windows extra that launches itself at logon "
        "— uncheck the keepers, clear the rest.",
        Meta="v0.1 · dynamic scan · dry run",
    ),
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.locks = {"fps": threading.Lock(), "startup": threading.Lock()}
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


app = FastAPI(title="PCTuner", lifespan=lifespan)


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


@app.post("/api/{tool}/apply", response_model=list[ApplyItemResult])
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

        try:
            ps_bridge.create_restore_point(f"PCTuner apply — {TOOL_META[tool].Name}")
        except ps_bridge.PSBridgeError:
            pass  # coarse safety net only; the undo log is the real one (§8.5)

        items_by_id = _catalog_by_id(tool)
        undo_log = reports.UndoLog(tool)
        results: list[ApplyItemResult] = []
        for result in ps_bridge.apply_sequential(items_by_id, checked_ids):
            undo_log.record(result, items_by_id[result.Id])
            results.append(result)

        reports.write_apply_report(tool, results)
        return results
    finally:
        lock.release()


@app.get("/api/{tool}/undo/available")
def get_undo_available(tool: str):
    _require_tool(tool)
    return {"available": reports.latest_undo_log(tool) is not None}


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
        return list(ps_bridge.undo_sequential(undo_records))
    finally:
        lock.release()


@app.post("/api/scan-pc", response_model=SystemInventory)
def post_scan_pc():
    scan = ps_bridge.run_system_scan()
    inventory = SystemInventory(**scan)
    app.state.system_scan = inventory
    app.state.pc_specs = inventory.Specs
    return inventory


@app.get("/api/scan-pc")
def get_scan_pc():
    return app.state.system_scan or JSONResponse(None)
