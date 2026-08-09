"""Subprocess bridge to the PowerShell engine (§5.5) — the single highest-risk
integration point in the rewrite. Every catalog fetch, scan, apply, and undo
tunnels through here.

Contract enforced throughout:
- Never salvage a broken call. Non-zero exit or unparsable JSON is always a
  hard PSBridgeError with stdout/stderr/returncode attached — a silently
  empty/default result would be actively misleading for a tool that
  eventually gates real system changes.
- `-Verb RunAs` is never used here. The parent process is already elevated
  (once app.py's elevation flow exists); child processes inherit that token
  automatically, so a per-call RunAs would trigger a fresh UAC prompt on
  every single scan.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from concurrent.futures import TimeoutError as FutureTimeoutError

from . import paths
from .models import ApplyItemResult, CatalogItem, ScanResult, UndoItemResult

CATALOG_TIMEOUT = 15.0
ITEM_TIMEOUT = 15.0
SCAN_OVERALL_TIMEOUT = 120.0
SCAN_MAX_WORKERS = 8
RESTORE_POINT_TIMEOUT = 30.0
SYSTEM_SCAN_TIMEOUT = 30.0


class PSHostNotFoundError(RuntimeError):
    """Neither pwsh.exe nor powershell.exe is on PATH."""


class PSBridgeError(RuntimeError):
    def __init__(
        self,
        item_id: str | None,
        message: str,
        *,
        returncode: int | None = None,
        stdout: str = "",
        stderr: str = "",
    ):
        self.item_id = item_id
        self.message = message
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
        super().__init__(f"[{item_id or '-'}] {message}")


_ps_exe: str | None = None


def resolve_ps_exe(force: bool = False) -> str:
    """Resolve once at startup and cache — mirrors PS-side Get-PrimePSExe."""
    global _ps_exe
    if _ps_exe and not force:
        return _ps_exe
    for candidate in ("pwsh", "powershell"):
        found = shutil.which(candidate)
        if found:
            _ps_exe = found
            return _ps_exe
    raise PSHostNotFoundError("No PowerShell host (pwsh or powershell.exe) found on this PC.")


def _run(args: list[str], *, item_id: str | None, timeout: float) -> str:
    ps_exe = resolve_ps_exe()
    cmd = [ps_exe, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", *args]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=timeout)
    except subprocess.TimeoutExpired as e:
        raise PSBridgeError(
            item_id, f"timed out after {timeout}s", stdout=e.stdout or "", stderr=e.stderr or ""
        ) from e

    if proc.returncode != 0:
        message = proc.stderr.strip() or f"script exited {proc.returncode}"
        try:
            obj = json.loads(proc.stdout)
            if isinstance(obj, dict) and obj.get("Error"):
                message = obj["Error"]
        except (json.JSONDecodeError, TypeError):
            pass
        raise PSBridgeError(
            item_id, message, returncode=proc.returncode, stdout=proc.stdout, stderr=proc.stderr
        )
    return proc.stdout


def _run_json(args: list[str], *, item_id: str | None, timeout: float) -> dict | list:
    stdout = _run(args, item_id=item_id, timeout=timeout)
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as e:
        raise PSBridgeError(item_id, f"malformed JSON output: {e}", returncode=0, stdout=stdout) from e


def _change_script_args(item: CatalogItem, mode: str, previous_value_json: str | None) -> list[str]:
    args = ["-File", item.ScriptPath, f"-{mode}"]
    for key, value in item.ScriptArgs.items():
        args += [f"-{key}", str(value)]
    if mode == "Undo" and previous_value_json:
        args += ["-PreviousValueJson", previous_value_json]
    return args


def run_change_item(
    item: CatalogItem, mode: str, previous_value_json: str | None = None, timeout: float = ITEM_TIMEOUT
) -> dict:
    """Invoke one changes\\*.ps1 script in one of Check/Apply/Undo mode.

    Placeholder rows (Enumerate.ps1's "nothing found" entries, ScriptPath is
    None) have no backing script — mirrors PS's Invoke-PrimeChangeScript,
    which treats them as always-compliant without a subprocess call.
    """
    if not item.ScriptPath:
        if mode == "Check":
            return {"Id": item.Id, "Mode": "Check", "Status": "APPLIED", "Current": "clean"}
        raise PSBridgeError(item.Id, f"{mode} is not implemented for placeholder item {item.Id}")

    args = _change_script_args(item, mode, previous_value_json)
    return _run_json(args, item_id=item.Id, timeout=timeout)


def scan_catalog(items: list[CatalogItem], checked_ids: set[str]) -> list[ScanResult]:
    """Read-only scan: unchecked items skip the subprocess entirely; checked
    items run concurrently (§5.5) since checks are independent/side-effect-free.
    """
    results: dict[str, ScanResult] = {}
    with ThreadPoolExecutor(max_workers=SCAN_MAX_WORKERS) as pool:
        futures = {}
        for item in items:
            if item.Id not in checked_ids:
                results[item.Id] = ScanResult(
                    Id=item.Id,
                    Name=item.Name,
                    Status="SKIPPED",
                    Current="(unchecked by user)",
                    Target=item.Target,
                )
                continue
            futures[pool.submit(run_change_item, item, "Check")] = item

        try:
            for future in as_completed(futures, timeout=SCAN_OVERALL_TIMEOUT):
                item = futures[future]
                try:
                    obj = future.result()
                    results[item.Id] = ScanResult(
                        Id=item.Id,
                        Name=item.Name,
                        Status=obj["Status"],
                        Current=obj["Current"],
                        Target=item.Target,
                    )
                except PSBridgeError as e:
                    results[item.Id] = ScanResult(
                        Id=item.Id,
                        Name=item.Name,
                        Status="ERROR",
                        Current=e.message,
                        Target=item.Target,
                    )
        except FutureTimeoutError:
            # Coarse circuit breaker (§5.5) — whatever didn't finish in the
            # overall window becomes a structured error, not a hang.
            for future, item in futures.items():
                if item.Id not in results:
                    future.cancel()
                    results[item.Id] = ScanResult(
                        Id=item.Id,
                        Name=item.Name,
                        Status="ERROR",
                        Current="scan timed out",
                        Target=item.Target,
                    )

    return [results[item.Id] for item in items]


def apply_sequential(items_by_id: dict[str, CatalogItem], checked_ids: list[str]):
    """Mutating — sequential, not pooled (§5.5, §8.5): safety and a simple
    incremental undo log matter more here than wall-clock time. Yields one
    ApplyItemResult at a time so the caller can write the undo log
    incrementally, per-success, never batched to the end.
    """
    for item_id in checked_ids:
        item = items_by_id[item_id]
        try:
            obj = run_change_item(item, "Apply")
            yield ApplyItemResult(**obj)
        except PSBridgeError as e:
            yield ApplyItemResult(Id=item_id, Success=False, Error=e.message)


def undo_sequential(undo_records: list[dict]):
    """`undo_records` are prior ApplyItemResult-shaped dicts (Id/PreviouslyExisted/
    PreviousValue/ScriptPath/ScriptArgs) from the most recent apply run's undo
    log — the exact shape the PS UndoBlock's `$Prev` parameter expects.

    Deliberately does NOT look the item back up in a freshly-loaded catalog:
    ScriptPath/ScriptArgs are snapshotted at apply time (reports.UndoLog.record),
    so Undo acts on exactly what Apply touched regardless of what the catalog
    looks like now. This matters for Startup Optimizer, whose catalog is
    re-enumerated live from the registry/task scheduler on every load — an
    item that Apply just removed may no longer appear at all, or a stale
    positional Id could otherwise resolve to a different, unrelated entry.
    """
    for record in undo_records:
        script_path = record.get("ScriptPath")
        if not script_path:
            yield UndoItemResult(
                Id=record["Id"],
                Success=False,
                Error="no script recorded for this item — apply log predates this format",
            )
            continue
        item = CatalogItem(
            Id=record["Id"],
            Level=0,
            Module="",
            Name="",
            Desc="",
            Target="",
            DefaultChecked=False,
            ScriptPath=script_path,
            ScriptArgs=record.get("ScriptArgs") or {},
        )
        prev_json = json.dumps(
            {
                "PreviouslyExisted": record.get("PreviouslyExisted"),
                "PreviousValue": record.get("PreviousValue"),
            }
        )
        try:
            obj = run_change_item(item, "Undo", previous_value_json=prev_json)
            yield UndoItemResult(**obj)
        except PSBridgeError as e:
            yield UndoItemResult(Id=record["Id"], Success=False, Error=e.message)


def check_game_running(timeout: float = 10.0) -> dict:
    """Live query, never the cached Scan PC process list (§6.7 safety
    carve-out) — a user could launch a game between scanning and applying.
    Reuses the existing Test-GameRunningTracked function via -Command
    instead of adding a new headless .ps1 file for one function call.
    """
    checks_path = paths.SHARED_DIR / "PrimeChecks.ps1"
    command = (
        "try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}; "
        f". '{checks_path}'; Test-GameRunningTracked | ConvertTo-Json -Compress"
    )
    return _run_json(["-Command", command], item_id=None, timeout=timeout)


def create_restore_point(description: str, timeout: float = RESTORE_POINT_TIMEOUT) -> dict:
    """Coarse safety net on top of the undo log, not instead of it (§8.5).
    Windows throttles to one per SystemRestorePointCreationFrequency (default
    24h) — that failure is expected and non-fatal, caught and reported, never
    raised, since the undo log remains the primary safety net regardless.
    """
    safe_desc = description.replace("'", "''")
    command = (
        "try { "
        f"Checkpoint-Computer -Description '{safe_desc}' "
        "-RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop; "
        "@{Success=$true;Note=$null} | ConvertTo-Json -Compress "
        "} catch { @{Success=$false;Note=$_.Exception.Message} | ConvertTo-Json -Compress }"
    )
    return _run_json(["-Command", command], item_id=None, timeout=timeout)


def run_system_scan(timeout: float = SYSTEM_SCAN_TIMEOUT) -> dict:
    script = paths.SHARED_DIR / "Invoke-SystemScan.ps1"
    return _run_json(["-File", str(script), "-Json"], item_id=None, timeout=timeout)


def run_enumerate_startup(timeout: float = CATALOG_TIMEOUT) -> list[dict]:
    script = paths.CHANGES_DIR / "PC Startup" / "Enumerate.ps1"
    result = _run_json(["-File", str(script), "-Json"], item_id=None, timeout=timeout)
    # PowerShell's `| ConvertTo-Json` collapses a single-item pipeline result
    # to a bare object rather than a 1-element array — guard against it even
    # though Enumerate.ps1 always emits >=3 rows (one per section) today.
    return result if isinstance(result, list) else [result]
