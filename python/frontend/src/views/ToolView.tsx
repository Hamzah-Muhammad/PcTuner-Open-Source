import { useCallback, useEffect, useState } from "react";
import {
  api,
  ApiError,
  type CatalogItem,
  type ScanResult,
  type ToolKey,
} from "../api";
import { Footer } from "../layout/Footer";
import { PageHeading } from "../layout/PageHeading";
import { SpecsPanel } from "../layout/SpecsPanel";
import { Topbar } from "../layout/Topbar";
import { ConfirmModal } from "../primitives/ConfirmModal";
import { ChecklistPanel, type LevelMeta } from "./ChecklistPanel";
import { ReportModal } from "./ReportModal";
import { StatsPanel, type ScanCounts } from "./StatsPanel";
import { ToolbarBar } from "./ToolbarBar";
import styles from "./ToolView.module.css";
import type { PCSpecs } from "../api";

interface ToolConfig {
  title: string;
  eyebrow: string;
  headingPlain: string;
  headingAccent: string;
  subtitle: string;
  footerNote: string;
  levelMeta: Record<number, LevelMeta>;
}

const TOOL_CONFIG: Record<ToolKey, ToolConfig> = {
  fps: {
    title: "FPS Optimizer",
    eyebrow: "PCTUNER · FOR GAMING RIGS",
    headingPlain: "FPS ",
    headingAccent: "Optimizer",
    subtitle:
      "Press Scan to check this PC against 54 known optimizations — ✓ APPLIED means already done. Uncheck anything you don't want, then Apply when ready: every change is logged and can be undone.",
    footerNote:
      "FPS Optimizer v0.3 · every applied change is logged and reversible",
    levelMeta: {
      1: { title: "LEVEL 1 · SAFE", color: "var(--muted)" },
      2: { title: "LEVEL 2 · DEBLOAT", color: "var(--red)" },
      3: { title: "LEVEL 3 · AGGRESSIVE", color: "var(--red-hi)" },
    },
  },
  startup: {
    title: "Startup Optimizer",
    eyebrow: "PCTUNER · FOR EVERYDAY PCs",
    headingPlain: "Startup ",
    headingAccent: "Optimizer",
    subtitle:
      "Press Scan to see every app, task, and Windows extra that launches itself at logon on this PC. ✓ APPLIED means already clean. Unchecked rows are recommended keeps. Apply makes real changes — each one is logged and can be undone.",
    footerNote:
      "Startup Optimizer v0.1 · every applied change is logged and reversible",
    levelMeta: {
      1: { title: "STARTUP APPS", color: "var(--muted)" },
      2: { title: "LOGON TASKS", color: "var(--red)" },
      3: { title: "WINDOWS EXTRAS", color: "var(--red-hi)" },
    },
  },
};

function formatAge(seconds: number): string {
  if (seconds < 60) return "less than a minute ago";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? "" : "s"} ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`;
  const days = Math.round(hours / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

const UNDO_STALE_AFTER_SECONDS = 24 * 60 * 60;

interface ToolViewProps {
  tool: ToolKey;
  specs: PCSpecs | null;
  onBack: () => void;
}

/** Ports New-PrimeChecklistApp + Invoke-PrimeScan — the branded checklist
 * window shared by both tools. Scan is one blocking POST /scan call (§6.6's
 * "ship the regression" decision), not a live per-row flip. */
export function ToolView({ tool, specs, onBack }: ToolViewProps) {
  const cfg = TOOL_CONFIG[tool];
  const [catalog, setCatalog] = useState<CatalogItem[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [scanning, setScanning] = useState(false);
  const [results, setResults] = useState<Map<string, ScanResult>>(new Map());
  const [counts, setCounts] = useState<ScanCounts | null>(null);
  const [reportAvailable, setReportAvailable] = useState(false);
  const [statusText, setStatusText] = useState(
    "Not scanned yet — press Scan to check",
  );
  const [applying, setApplying] = useState(false);
  const [undoing, setUndoing] = useState(false);
  const [undoAvailable, setUndoAvailable] = useState(false);
  const [undoAgeSeconds, setUndoAgeSeconds] = useState<number | null>(null);
  const [showApplyModal, setShowApplyModal] = useState(false);
  const [showUndoModal, setShowUndoModal] = useState(false);
  const [showReportModal, setShowReportModal] = useState(false);
  // Per-item Apply/Undo failures, surfaced explicitly — without this, a
  // partial failure (e.g. Access Denied on one service) was indistinguishable
  // in the UI from the user simply not having checked that item, since the
  // backend's per-item Error/Note was fetched and then never read.
  const [itemErrors, setItemErrors] = useState<
    { Id: string; message: string }[]
  >([]);

  const runScan = useCallback(
    async (ids: string[]) => {
      setScanning(true);
      setStatusText("Scanning…");
      try {
        const scanResults = await api.scan(tool, ids);
        const map = new Map(scanResults.map((r) => [r.Id, r]));
        const c: ScanCounts = {
          applied: 0,
          pending: 0,
          review: 0,
          skipped: 0,
          errors: 0,
        };
        for (const r of scanResults) {
          if (r.Status === "APPLIED") c.applied++;
          else if (r.Status === "PENDING") c.pending++;
          else if (r.Status === "REVIEW") c.review++;
          else if (r.Status === "SKIPPED") c.skipped++;
          else if (r.Status === "ERROR") c.errors++;
        }
        setResults(map);
        setCounts(c);
        setReportAvailable(true);
        setStatusText(
          `${c.applied} applied · ${c.pending} pending · ${c.review} review · ` +
            `${c.skipped} skipped · ${c.errors} errors`,
        );
      } catch (e) {
        setStatusText(
          `Scan failed: ${e instanceof Error ? e.message : "unknown error"}`,
        );
      } finally {
        setScanning(false);
      }
    },
    [tool],
  );

  const refreshUndoAvailable = useCallback(async () => {
    try {
      const { available, ageSeconds } = await api.undoAvailable(tool);
      setUndoAvailable(available);
      setUndoAgeSeconds(ageSeconds);
    } catch {
      // Non-critical — leave whatever the button already shows rather than
      // surface a status-text error for a background availability check.
    }
  }, [tool]);

  const refreshReportAvailable = useCallback(async () => {
    // "Open report" used to start disabled on every fresh launch, even when
    // a real DryRun_*.md report from an earlier session already exists on
    // disk — reportAvailable was pure session state, never checked against
    // what's actually there. A 404 here just means no report yet, which is
    // the normal case right after launch.
    try {
      await api.latestReport(tool);
      setReportAvailable(true);
    } catch {
      setReportAvailable(false);
    }
  }, [tool]);

  useEffect(() => {
    // No auto-scan on load — the catalog renders with every row IDLE
    // ("not scanned") until the user presses Scan. Cancellation guard is
    // still needed for StrictMode's dev-mode double-invoke (mount →
    // cleanup → mount), since the catalog fetch itself is async.
    let cancelled = false;
    setCatalog(null);
    setResults(new Map());
    setCounts(null);
    setStatusText("Not scanned yet — press Scan to check");
    setUndoAvailable(false);
    api
      .catalog(tool)
      .then((items) => {
        if (cancelled) return;
        setCatalog(items);
        const defaultChecked = new Set(
          items.filter((i) => i.DefaultChecked).map((i) => i.Id),
        );
        setChecked(defaultChecked);
      })
      .catch((e) => {
        if (!cancelled) setLoadError(e.message ?? "failed to load catalog");
      });
    refreshUndoAvailable();
    refreshReportAvailable();
    return () => {
      cancelled = true;
    };
  }, [tool, refreshUndoAvailable, refreshReportAvailable]);

  const toggle = (id: string, isChecked: boolean) => {
    setChecked((prev) => {
      const next = new Set(prev);
      if (isChecked) next.add(id);
      else next.delete(id);
      return next;
    });
  };

  const selectAll = () =>
    catalog && setChecked(new Set(catalog.map((i) => i.Id)));
  const selectNone = () => setChecked(new Set());
  const uncheckLevel3 = () =>
    catalog &&
    setChecked((prev) => {
      const l3 = new Set(catalog.filter((i) => i.Level === 3).map((i) => i.Id));
      return new Set([...prev].filter((id) => !l3.has(id)));
    });
  const openReport = () => setShowReportModal(true);

  // Eligibility is derived, never trusted as-is by the server (§8.5) — this
  // is purely so the confirmation modal can tell the user an accurate count
  // before firing. checked ids that aren't PENDING on the last scan (e.g.
  // already APPLIED, or never scanned) are silently excluded here too, same
  // rule the backend re-enforces.
  const eligibleIds = [...checked].filter(
    (id) => results.get(id)?.Status === "PENDING",
  );
  const eligibleLevel3Count =
    catalog?.filter((i) => eligibleIds.includes(i.Id) && i.Level === 3)
      .length ?? 0;

  const describeError = (e: unknown) =>
    e instanceof ApiError
      ? e.detail
      : e instanceof Error
        ? e.message
        : "unknown error";

  const confirmApply = async () => {
    setShowApplyModal(false);
    setApplying(true);
    setItemErrors([]);
    setStatusText(
      `Applying ${eligibleIds.length} change${eligibleIds.length === 1 ? "" : "s"}…`,
    );
    try {
      const {
        Results: results,
        RestorePointOk,
        RestorePointNote,
      } = await api.apply(tool, eligibleIds);
      const failed = results.filter((r) => !r.Success);
      const errors = failed.map((r) => ({
        Id: r.Id,
        message: r.Error || r.Note || "failed",
      }));
      if (!RestorePointOk) {
        // Not a per-item failure — the confirm modal promised a restore
        // point would be created first, so a silent failure here would be
        // a broken promise, not a harmless one. The undo log is unaffected.
        errors.push({
          Id: "Restore Point",
          message:
            RestorePointNote ||
            "could not be created — the undo log below is still intact",
        });
      }
      if (errors.length) setItemErrors(errors);
      // Re-scan rather than hand-reconcile apply results into `results` —
      // the scan is the actual source of truth for current system state,
      // and this reuses the exact same rendering path a manual re-scan does.
      await runScan([...checked]);
      await refreshUndoAvailable();
    } catch (e) {
      setStatusText(`Apply failed: ${describeError(e)}`);
    } finally {
      setApplying(false);
    }
  };

  const confirmUndo = async () => {
    setShowUndoModal(false);
    setUndoing(true);
    setItemErrors([]);
    setStatusText("Undoing last apply run…");
    try {
      const results = await api.undo(tool);
      const failed = results.filter((r) => !r.Success);
      if (failed.length) {
        setItemErrors(
          failed.map((r) => ({
            Id: r.Id,
            message: r.Error || r.Note || "failed",
          })),
        );
      }
      await runScan([...checked]);
      await refreshUndoAvailable();
    } catch (e) {
      setStatusText(`Undo failed: ${describeError(e)}`);
    } finally {
      setUndoing(false);
    }
  };

  return (
    <div className={styles.page}>
      <div className={styles.topRow}>
        <button className={styles.back} onClick={onBack}>
          ← HUB
        </button>
        <Topbar />
      </div>
      <PageHeading
        eyebrow={cfg.eyebrow}
        headingPlain={cfg.headingPlain}
        headingAccent={cfg.headingAccent}
        subtitle={cfg.subtitle}
        size="md"
      />

      <div className={styles.metaRow}>
        {specs && <SpecsPanel specs={specs} />}
        <div className={styles.statsRow}>
          <StatsPanel counts={counts} />
        </div>
      </div>

      {loadError && (
        <div className={styles.error}>Couldn't load catalog: {loadError}</div>
      )}

      {itemErrors.length > 0 && (
        <div className={styles.itemErrors}>
          <div className={styles.itemErrorsTitle}>
            {itemErrors.length} thing{itemErrors.length === 1 ? "" : "s"} worth
            knowing — nothing here was silently hidden:
          </div>
          <ul className={styles.itemErrorsList}>
            {itemErrors.map((e) => (
              <li key={e.Id}>
                <span className={styles.itemErrorId}>{e.Id}</span> {e.message}
              </li>
            ))}
          </ul>
        </div>
      )}
      {!catalog && !loadError && (
        <div className={styles.loading}>Loading catalog…</div>
      )}

      {catalog && (
        <div className={styles.checklistWrap}>
          <ChecklistPanel
            items={catalog}
            levelMeta={cfg.levelMeta}
            checkedIds={checked}
            onToggle={toggle}
            results={results}
            scanning={scanning}
          />
          <ToolbarBar
            onSelectAll={selectAll}
            onSelectNone={selectNone}
            onUncheckLevel3={uncheckLevel3}
            onOpenReport={openReport}
            reportAvailable={reportAvailable}
            statusText={statusText}
            onRescan={() => runScan([...checked])}
            scanning={scanning}
            hasScanned={counts !== null}
            onApply={() => setShowApplyModal(true)}
            applyEnabled={counts !== null && eligibleIds.length > 0}
            applying={applying}
            onUndo={() => setShowUndoModal(true)}
            undoEnabled={undoAvailable}
            undoing={undoing}
          />
        </div>
      )}

      {showApplyModal && (
        <ConfirmModal
          title="Apply changes?"
          message={
            `About to apply ${eligibleIds.length} change${eligibleIds.length === 1 ? "" : "s"} ` +
            "to this PC — a System Restore Point will be created first, and every change is " +
            "logged so it can be undone afterward. Use at your own risk: the author isn't " +
            "responsible for any damage to your PC or data loss from applying these changes."
          }
          callout={
            eligibleLevel3Count > 0
              ? `${eligibleLevel3Count} of these ${eligibleLevel3Count === 1 ? "is" : "are"} ` +
                `${cfg.levelMeta[3].title} — the most aggressive tier in this tool.`
              : undefined
          }
          confirmLabel="Apply"
          onConfirm={confirmApply}
          onCancel={() => setShowApplyModal(false)}
        />
      )}

      {showUndoModal && (
        <ConfirmModal
          title="Undo last apply?"
          message={
            `This reverts every change from the most recent apply run for this tool back to its ` +
            `previous value${undoAgeSeconds != null ? ` (applied ${formatAge(undoAgeSeconds)})` : ""}. ` +
            "There's no per-item undo — it's all or nothing."
          }
          callout={
            undoAgeSeconds != null && undoAgeSeconds > UNDO_STALE_AFTER_SECONDS
              ? `That apply run was ${formatAge(undoAgeSeconds)} — a lot may have changed on this PC ` +
                "since then. Make sure this is still what you want to revert."
              : undefined
          }
          confirmLabel="Undo"
          onConfirm={confirmUndo}
          onCancel={() => setShowUndoModal(false)}
        />
      )}

      {showReportModal && (
        <ReportModal tool={tool} onClose={() => setShowReportModal(false)} />
      )}

      <Footer note={cfg.footerNote} />
    </div>
  );
}
