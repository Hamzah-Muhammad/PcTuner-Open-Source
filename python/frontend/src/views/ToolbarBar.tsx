import { Button } from "../primitives/Button";
import styles from "./ToolbarBar.module.css";

interface ToolbarBarProps {
  onSelectAll: () => void;
  onSelectNone: () => void;
  onUncheckLevel3: () => void;
  onOpenReport: () => void;
  reportAvailable: boolean;
  statusText: string;
  onRescan: () => void;
  scanning: boolean;
  hasScanned: boolean;
  onApply: () => void;
  applyEnabled: boolean;
  applying: boolean;
  onUndo: () => void;
  undoEnabled: boolean;
  undoing: boolean;
}

/** Ports the bottom DockPanel toolbar (Grid.Row=4) from New-PrimeChecklistApp.
 * No scan runs automatically (user directive) — this button is the only
 * trigger, first scan and every one after. Apply/Undo are a new addition
 * (the original WPF app was dry-run only) — both open a confirmation modal
 * in ToolView rather than firing directly from here. */
export function ToolbarBar({
  onSelectAll,
  onSelectNone,
  onUncheckLevel3,
  onOpenReport,
  reportAvailable,
  statusText,
  onRescan,
  scanning,
  hasScanned,
  onApply,
  applyEnabled,
  applying,
  onUndo,
  undoEnabled,
  undoing,
}: ToolbarBarProps) {
  return (
    <div className={styles.bar}>
      <div className={styles.left}>
        <Button onClick={onSelectAll}>Select all</Button>
        <Button onClick={onSelectNone}>Select none</Button>
        <Button onClick={onUncheckLevel3}>Uncheck Level 3</Button>
        <Button onClick={onOpenReport} disabled={!reportAvailable}>
          Open report
        </Button>
        <Button onClick={onUndo} disabled={!undoEnabled || undoing}>
          {undoing ? "Undoing…" : "Undo last apply"}
        </Button>
      </div>
      <div className={styles.right}>
        <span className={styles.status}>{statusText}</span>
        <Button
          variant="primary"
          onClick={onRescan}
          disabled={scanning || applying}
        >
          {hasScanned ? "Re-scan" : "Scan"}
        </Button>
        <Button
          variant="danger"
          onClick={onApply}
          disabled={!applyEnabled || applying || scanning}
        >
          {applying ? "Applying…" : "Apply"}
        </Button>
      </div>
    </div>
  );
}
