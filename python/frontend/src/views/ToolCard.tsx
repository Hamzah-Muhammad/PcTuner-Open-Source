import type { ToolMeta } from "../api";
import { Button } from "../primitives/Button";
import { Card } from "../primitives/Card";
import styles from "./ToolCard.module.css";

interface ToolCardProps {
  tool: ToolMeta;
  onLaunch: () => void;
}

const TAG_COLOR: Record<string, string> = {
  fps: "var(--green)",
  startup: "var(--gold-a)",
};

/** Ports the tool-launch card built inline in PrimePCTuner.ps1's foreach loop. */
export function ToolCard({ tool, onLaunch }: ToolCardProps) {
  return (
    <Card interactive>
      <div className={styles.row}>
        <div className={styles.texts}>
          <div className={styles.titleLine}>
            <span className={styles.name}>{tool.Name}</span>
            <span className={styles.tag} style={{ color: TAG_COLOR[tool.Key] }}>
              {tool.Tag}
            </span>
          </div>
          <p className={styles.desc}>{tool.Desc}</p>
          <div className={styles.meta}>{tool.Meta}</div>
        </div>
        <Button
          variant="primary"
          className={styles.launchBtn}
          onClick={onLaunch}
        >
          Launch →
        </Button>
      </div>
    </Card>
  );
}
