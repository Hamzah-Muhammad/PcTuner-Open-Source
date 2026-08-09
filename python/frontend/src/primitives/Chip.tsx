import type { ReactNode } from "react";
import styles from "./Chip.module.css";

interface ChipProps {
  label: string;
  value: ReactNode;
  valueColor?: string;
}

/** Ports the "Chip" XAML Style — used for spec chips and scan-stat chips. */
export function Chip({ label, value, valueColor }: ChipProps) {
  return (
    <span className={styles.chip}>
      <span className={styles.label}>{label}</span>
      <span
        className={styles.value}
        style={valueColor ? { color: valueColor } : undefined}
      >
        {value}
      </span>
    </span>
  );
}
