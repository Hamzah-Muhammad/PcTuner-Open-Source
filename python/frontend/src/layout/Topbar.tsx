import styles from "./Topbar.module.css";

interface TopbarProps {
  healthWarning?: string | null;
}

/** Ports Get-PrimeTopbarXaml — the glowing green dot + "@Humzeeny" mark shown
 * on every window. The optional health pill has no WPF equivalent (the WPF
 * app just shows a blocking MessageBox on the same condition) — added so a
 * missing PowerShell host degrades visibly instead of silently. */
export function Topbar({ healthWarning }: TopbarProps) {
  return (
    <div className={styles.topbar}>
      <span className={styles.statusDot} />
      <span className={styles.handle}>
        <span className={styles.at}>@</span>
        <span>Humzeeny</span>
      </span>
      {healthWarning && (
        <span
          style={{
            marginLeft: 12,
            fontSize: 11,
            fontWeight: 700,
            color: "var(--red)",
            border: "1px solid var(--red)",
            borderRadius: 8,
            padding: "2px 8px",
          }}
        >
          {healthWarning}
        </span>
      )}
    </div>
  );
}
