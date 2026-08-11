import { PrimeBrand } from "./PrimeBrand";
import styles from "./Topbar.module.css";

interface TopbarProps {
  healthWarning?: string | null;
}

/** Ports Get-PrimeTopbarXaml — the glowing status dot shown on every window,
 * now paired with the Prime Investing Capital mark. The optional health pill
 * has no WPF equivalent (the WPF app just shows a blocking MessageBox on the
 * same condition) — added so a missing PowerShell host degrades visibly
 * instead of silently. */
export function Topbar({ healthWarning }: TopbarProps) {
  return (
    <div className={styles.topbar}>
      <span className={styles.statusDot} />
      <PrimeBrand />
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
