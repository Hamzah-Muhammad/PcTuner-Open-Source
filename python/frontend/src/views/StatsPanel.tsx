import styles from "./StatsPanel.module.css";

export interface ScanCounts {
  applied: number;
  pending: number;
  review: number;
  skipped: number;
  errors: number;
}

// True monochrome except errors (red/black rebrand, 2026-08-09) — matches
// StatusPill's scheme so the summary chips and per-row pills read the same way.
const STAT_DEFS: { key: keyof ScanCounts; label: string; color: string }[] = [
  { key: "applied", label: "APPLIED", color: "var(--text)" },
  { key: "pending", label: "PENDING", color: "var(--muted)" },
  { key: "review", label: "REVIEW", color: "var(--muted)" },
  { key: "skipped", label: "SKIPPED", color: "var(--muted-dim)" },
  { key: "errors", label: "ERRORS", color: "var(--red)" },
];

interface StatsPanelProps {
  counts: ScanCounts | null;
}

/** Ports the scan-stat chip row built inline in New-PrimeChecklistApp. */
export function StatsPanel({ counts }: StatsPanelProps) {
  return (
    <div className={styles.panel}>
      {STAT_DEFS.map((sd) => (
        <span className={styles.chip} key={sd.key}>
          <span className={styles.dot} style={{ color: sd.color }}>
            ●
          </span>
          <span className={styles.num}>{counts ? counts[sd.key] : "–"}</span>
          <span className={styles.label}>{sd.label}</span>
        </span>
      ))}
    </div>
  );
}
