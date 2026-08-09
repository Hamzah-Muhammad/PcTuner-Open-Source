import styles from "./StatsPanel.module.css";

export interface ScanCounts {
  applied: number;
  pending: number;
  review: number;
  skipped: number;
  errors: number;
}

const STAT_DEFS: { key: keyof ScanCounts; label: string; color: string }[] = [
  { key: "applied", label: "APPLIED", color: "var(--green)" },
  { key: "pending", label: "PENDING", color: "var(--gold-a)" },
  { key: "review", label: "REVIEW", color: "var(--muted)" },
  { key: "skipped", label: "SKIPPED", color: "var(--muted)" },
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
