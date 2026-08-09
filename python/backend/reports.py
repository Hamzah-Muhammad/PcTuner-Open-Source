"""Report + log writers. Ported from PS's Invoke-PrimeScan (§5) rather than
kept PS-side — it's plain string/JSON writing, no reason to shell out for it.

Report/log location is unchanged from today: each tool's own logs\\ folder.
"""

import json
import time
from datetime import datetime
from pathlib import Path

from . import paths
from .models import ApplyItemResult, CatalogItem, PCSpecs, ScanResult

REPORT_TITLES = {"fps": "FPS Optimizer dry run", "startup": "Startup Optimizer dry run"}


def _timestamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def _counts(results: list[ScanResult]) -> dict[str, int]:
    counts = {"applied": 0, "pending": 0, "review": 0, "skipped": 0, "errors": 0}
    key_by_status = {
        "APPLIED": "applied",
        "PENDING": "pending",
        "REVIEW": "review",
        "SKIPPED": "skipped",
        "ERROR": "errors",
    }
    for r in results:
        counts[key_by_status[r.Status]] += 1
    return counts


def write_scan_report(tool_key: str, specs: PCSpecs | None, results: list[ScanResult]) -> Path:
    log_dir = paths.logs_dir(tool_key)
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = _timestamp()
    counts = _counts(results)
    title = REPORT_TITLES[tool_key]

    # specs is None whenever a catalog scan runs without Scan PC having been
    # pressed first — the two are independent, button-triggered scans (no
    # scan of any kind runs automatically), so this is a normal case, not an
    # error.
    system_line = f"**System:** {specs.CPU} · {specs.GPU} · {specs.RAM} · {specs.OS}" if specs else (
        "**System:** not scanned — press Scan PC on the hub for system info in this report."
    )
    lines = [
        f"# {title} — {datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "",
        system_line,
        f"**Result:** {counts['applied']} applied · {counts['pending']} pending · "
        f"{counts['review']} review · {counts['skipped']} skipped · {counts['errors']} errors. "
        "Nothing was changed.",
        "",
        "| Id | Item | Status | Current | Target |",
        "|---|---|---|---|---|",
    ]
    for r in results:
        current = r.Current.replace("|", "/")
        target = r.Target.replace("|", "/")
        lines.append(f"| {r.Id} | {r.Name} | {r.Status} | {current} | {target} |")

    md_path = log_dir / f"DryRun_{ts}.md"
    json_path = log_dir / f"DryRun_{ts}.json"
    md_path.write_text("\n".join(lines), encoding="utf-8")
    json_path.write_text(json.dumps([r.model_dump() for r in results], indent=2), encoding="utf-8")
    return md_path


def latest_scan_report(tool_key: str) -> dict | None:
    log_dir = paths.logs_dir(tool_key)
    if not log_dir.is_dir():
        return None
    reports = sorted(log_dir.glob("DryRun_*.json"))
    if not reports:
        return None
    latest = reports[-1]
    return {"path": str(latest), "results": json.loads(latest.read_text(encoding="utf-8"))}


def latest_scan_report_markdown(tool_key: str) -> str | None:
    """The human-readable report `write_scan_report` already writes right
    next to the JSON one — "Open report" used to point at the raw JSON
    (`latest_scan_report` above) instead of this, which is what it was
    actually meant to show."""
    log_dir = paths.logs_dir(tool_key)
    if not log_dir.is_dir():
        return None
    reports = sorted(log_dir.glob("DryRun_*.md"))
    if not reports:
        return None
    return reports[-1].read_text(encoding="utf-8")


def write_apply_report(tool_key: str, results: list[ApplyItemResult]) -> Path:
    log_dir = paths.logs_dir(tool_key)
    log_dir.mkdir(parents=True, exist_ok=True)
    ts = _timestamp()
    succeeded = sum(1 for r in results if r.Success)
    failed = len(results) - succeeded

    lines = [
        f"# {REPORT_TITLES[tool_key].replace('dry run', 'apply run')} — "
        f"{datetime.now().strftime('%Y-%m-%d %H:%M')}",
        "",
        f"**Result:** {succeeded} applied · {failed} failed.",
        "",
        "| Id | Success | Note |",
        "|---|---|---|",
    ]
    for r in results:
        note = (r.Note or r.Error or "").replace("|", "/")
        lines.append(f"| {r.Id} | {r.Success} | {note} |")

    md_path = log_dir / f"ApplyLog_{ts}.md"
    json_path = log_dir / f"ApplyLog_{ts}.json"
    md_path.write_text("\n".join(lines), encoding="utf-8")
    json_path.write_text(json.dumps([r.model_dump() for r in results], indent=2), encoding="utf-8")
    return md_path


class UndoLog:
    """Incremental undo log — one record written per successful apply item,
    never batched to the end (§8.5). Overwrites the whole (small) file on
    every append rather than true line-appends, so the file is always valid,
    complete JSON if the process is killed mid-run.
    """

    def __init__(self, tool_key: str):
        log_dir = paths.logs_dir(tool_key)
        log_dir.mkdir(parents=True, exist_ok=True)
        self.path = log_dir / f"UndoLog_{_timestamp()}.json"
        self._records: list[dict] = []

    def record(self, result: ApplyItemResult, item: CatalogItem) -> None:
        if not result.Success:
            return
        # ScriptPath/ScriptArgs are snapshotted from the exact item that was
        # just applied, not re-resolved from a fresh catalog lookup at undo
        # time. This matters most for Startup Optimizer: a fresh catalog
        # reload re-enumerates the PC's live registry/tasks, and if the item
        # this record is FOR was itself just removed, undo would otherwise
        # have no way to find it — or worse, silently resolve to a different
        # entry that happens to reuse the same Id after re-enumeration.
        # Storing the real target here means Undo never needs the catalog at
        # all: it acts on exactly what Apply actually touched.
        self._records.append(
            {
                "Id": result.Id,
                "PreviouslyExisted": result.PreviouslyExisted,
                "PreviousValue": result.PreviousValue,
                "ScriptPath": item.ScriptPath,
                "ScriptArgs": item.ScriptArgs,
            }
        )
        self.path.write_text(json.dumps(self._records, indent=2), encoding="utf-8")


def _latest_undo_log_path(tool_key: str) -> Path | None:
    log_dir = paths.logs_dir(tool_key)
    if not log_dir.is_dir():
        return None
    logs = sorted(log_dir.glob("UndoLog_*.json"))
    return logs[-1] if logs else None


def latest_undo_log(tool_key: str) -> list[dict] | None:
    path = _latest_undo_log_path(tool_key)
    if path is None:
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def undo_log_age_seconds(tool_key: str) -> float | None:
    """None means no undo log exists at all (mirrors latest_undo_log). Used
    so the UI can warn before replaying an old snapshot instead of silently
    offering it forever with no indication of how stale it is."""
    path = _latest_undo_log_path(tool_key)
    if path is None:
        return None
    return max(0.0, time.time() - path.stat().st_mtime)


def retire_undo_log(tool_key: str) -> None:
    """Renames (never deletes — keeps the historical record on disk, same
    posture as every other report/log here) the most recent undo log once
    it's been fully, successfully replayed, so "Undo last apply" can't fire
    a second time against a run that's already been undone. Only call this
    after every item in the run succeeded — a partial failure should leave
    the log in place so the user can retry."""
    path = _latest_undo_log_path(tool_key)
    if path is None:
        return
    path.rename(path.with_name(f"Consumed{path.name}"))
