import primeLogoImg from "../assets/prime-logo.png";
import styles from "./PrimeBrand.module.css";

interface PrimeBrandProps {
  size?: number;
}

/** The real Prime Investing Capital mark — the same file already live on
 * primeinvestingcapital.com and The Edge (see their own PrimeLogo/Logo
 * components), not an invented one. */
export function PrimeBrand({ size = 18 }: PrimeBrandProps) {
  const height = size;
  const width = Math.round(size * (190 / 165));
  return (
    <span className={styles.brand}>
      <img
        src={primeLogoImg}
        alt="Prime Investing Capital"
        width={width}
        height={height}
        className={styles.logo}
      />
      <span className={styles.name}>Prime Investing Capital</span>
    </span>
  );
}
