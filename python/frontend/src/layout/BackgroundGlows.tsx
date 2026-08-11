import styles from "./BackgroundGlows.module.css";

/** Ports the two RadialGradientBrush Ellipses from PrimeUI.ps1's Get-PrimeGlowsXaml. */
export function BackgroundGlows() {
  return (
    <div className={styles.glows} aria-hidden="true">
      <div className={styles.glowTop} />
      <div className={styles.glowBottom} />
    </div>
  );
}
