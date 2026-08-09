import styles from "./Footer.module.css";

interface FooterProps {
  note: string;
}

export function Footer({ note }: FooterProps) {
  return (
    <div className={styles.footer}>
      <span>
        <span className={styles.at}>@</span>Humzeeny
      </span>
      <span>{note}</span>
    </div>
  );
}
