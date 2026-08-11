import { type MouseEvent, useEffect, useState } from "react";
import { api, type ToolKey } from "../api";
import { Button } from "../primitives/Button";
import { Card } from "../primitives/Card";
import styles from "./ReportModal.module.css";

interface ReportModalProps {
  tool: ToolKey;
  onClose: () => void;
}

/** Shows the latest dry-run/apply report inline instead of window.open()'ing
 * it — pywebview's embedded WebView2 treats window.open(url, "_blank") as a
 * new-window request and hands it to the OS default browser (webview's
 * documented behavior for external links), so the old implementation kicked
 * users straight out of the desktop app into a browser tab on every
 * "Open report" click. Fetching the text and rendering it in a modal keeps
 * everything inside the app window, which is the whole point of shipping
 * this as a standalone .exe rather than a website. */
export function ReportModal({ tool, onClose }: ReportModalProps) {
  const [text, setText] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    api
      .latestReportMarkdown(tool)
      .then((t) => {
        if (!cancelled) setText(t);
      })
      .catch((e) => {
        if (!cancelled)
          setError(e instanceof Error ? e.message : "failed to load report");
      });
    return () => {
      cancelled = true;
    };
  }, [tool]);

  return (
    <div className={styles.overlay} onClick={onClose}>
      <Card
        className={styles.card}
        onClick={(e: MouseEvent) => e.stopPropagation()}
      >
        <div className={styles.header}>
          <h3 className={styles.title}>Latest report</h3>
          <Button onClick={onClose}>Close</Button>
        </div>
        <div className={styles.body}>
          {error && <div className={styles.error}>Couldn't load report: {error}</div>}
          {!error && text === null && (
            <div className={styles.loading}>Loading…</div>
          )}
          {!error && text !== null && <pre className={styles.text}>{text}</pre>}
        </div>
      </Card>
    </div>
  );
}
