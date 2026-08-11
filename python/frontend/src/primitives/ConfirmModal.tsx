import type { MouseEvent, ReactNode } from "react";
import { Button } from "./Button";
import { Card } from "./Card";
import styles from "./ConfirmModal.module.css";

interface ConfirmModalProps {
  title: string;
  message: ReactNode;
  callout?: ReactNode;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
}

/** Generic destructive-action confirmation dialog — new addition, not in the
 * original WPF app (which had no apply/undo UI, dry-run only). Used by both
 * the Apply and Undo flows per §8.5's "requires an explicit second
 * confirmation modal before firing" decision. */
export function ConfirmModal({
  title,
  message,
  callout,
  confirmLabel,
  onConfirm,
  onCancel,
}: ConfirmModalProps) {
  return (
    <div className={styles.modalOverlay} onClick={onCancel}>
      <Card
        className={styles.modalCard}
        onClick={(e: MouseEvent) => e.stopPropagation()}
      >
        <h3 className={styles.modalTitle}>{title}</h3>
        <div className={styles.modalMessage}>{message}</div>
        {callout && <div className={styles.modalCallout}>{callout}</div>}
        <div className={styles.modalActions}>
          <Button onClick={onCancel}>Cancel</Button>
          <Button variant="danger" onClick={onConfirm}>
            {confirmLabel}
          </Button>
        </div>
      </Card>
    </div>
  );
}
