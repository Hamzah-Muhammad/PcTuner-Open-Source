import type { ButtonHTMLAttributes } from "react";
import styles from "./Button.module.css";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "danger";
}

/** Ports the BtnPri / BtnSec XAML Styles. "danger" is a new addition (not in
 * the original WPF app, which had no apply/undo UI) for the apply/undo
 * confirmation flow — Primary is outlined red, Danger is solid-filled red,
 * so the destructive action still carries more visual weight. */
export function Button({
  variant = "secondary",
  className,
  ...rest
}: ButtonProps) {
  const variantClass =
    variant === "primary"
      ? styles.btnPri
      : variant === "danger"
        ? styles.btnDanger
        : styles.btnSec;
  return (
    <button
      className={[styles.btn, variantClass, className]
        .filter(Boolean)
        .join(" ")}
      {...rest}
    />
  );
}
