import styles from "./PageHeading.module.css";

interface PageHeadingProps {
  eyebrow: string;
  headingPlain: string;
  headingAccent: string;
  subtitle: string;
  size?: "lg" | "md";
}

/** Ports the eyebrow/heading/subtitle StackPanel repeated in both
 * PrimePCTuner.ps1 (size lg, 34px) and New-PrimeChecklistApp (size md, 30px). */
export function PageHeading({
  eyebrow,
  headingPlain,
  headingAccent,
  subtitle,
  size = "lg",
}: PageHeadingProps) {
  return (
    <div className={styles.heading}>
      <div className={styles.eyebrow}>{eyebrow}</div>
      <h1
        className={styles.title}
        style={{ fontSize: size === "lg" ? 34 : 30 }}
      >
        {headingPlain}
        <span className={styles.accent}>{headingAccent}</span>
      </h1>
      <p className={styles.subtitle}>{subtitle}</p>
    </div>
  );
}
