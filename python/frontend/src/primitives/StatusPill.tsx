import styles from "./StatusPill.module.css";

export type PillStatus =
  "IDLE" | "SCANNING" | "APPLIED" | "PENDING" | "REVIEW" | "SKIPPED" | "ERROR";

const STYLES: Record<
  PillStatus,
  { text: string; fg: string; border: string; bg: string }
> = {
  IDLE: {
    text: "NOT SCANNED",
    fg: "var(--muted)",
    border: "var(--border)",
    bg: "var(--pill-bg)",
  },
  SCANNING: {
    text: "… SCANNING",
    fg: "var(--muted)",
    border: "var(--border)",
    bg: "var(--pill-bg)",
  },
  APPLIED: {
    text: "✓ APPLIED",
    fg: "var(--green-hi)",
    border: "var(--green)",
    bg: "color-mix(in srgb, var(--green) 12%, transparent)",
  },
  PENDING: {
    text: "→ PENDING",
    fg: "var(--gold-a)",
    border: "var(--gold-b)",
    bg: "color-mix(in srgb, var(--gold-a) 14%, transparent)",
  },
  REVIEW: {
    text: "◆ REVIEW",
    fg: "var(--review-fg)",
    border: "var(--muted)",
    bg: "var(--pill-bg)",
  },
  SKIPPED: {
    text: "SKIPPED",
    fg: "var(--muted)",
    border: "var(--border)",
    bg: "var(--pill-bg)",
  },
  ERROR: {
    text: "✕ ERROR",
    fg: "var(--red)",
    border: "var(--red)",
    bg: "color-mix(in srgb, var(--red) 12%, transparent)",
  },
};

interface StatusPillProps {
  status: PillStatus;
  detail?: string;
}

/** Ports $PillStyles + Set-PrimeRowStatus. */
export function StatusPill({ status, detail }: StatusPillProps) {
  const s = STYLES[status];
  return (
    <div className={styles.wrap}>
      <span
        className={
          styles.pill + (status === "SCANNING" ? ` ${styles.scanning}` : "")
        }
        style={{ color: s.fg, borderColor: s.border, background: s.bg }}
      >
        {s.text}
      </span>
      {detail && <div className={styles.detail}>{detail}</div>}
    </div>
  );
}
