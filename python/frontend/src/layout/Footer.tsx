import { PrimeBrand } from "./PrimeBrand";
import styles from "./Footer.module.css";

interface FooterProps {
  note: string;
}

export function Footer({ note }: FooterProps) {
  return (
    <div className={styles.footer}>
      <PrimeBrand size={16} />
      <span>{note}</span>
    </div>
  );
}
