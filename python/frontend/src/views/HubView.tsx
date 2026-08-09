import type { ToolKey, ToolsResponse } from "../api";
import { Footer } from "../layout/Footer";
import { PageHeading } from "../layout/PageHeading";
import { SpecsPanel } from "../layout/SpecsPanel";
import { Topbar } from "../layout/Topbar";
import { Button } from "../primitives/Button";
import { ToolCard } from "./ToolCard";
import styles from "./HubView.module.css";

interface HubViewProps {
  data: ToolsResponse | null;
  error: string | null;
  healthWarning: string | null;
  version: string | null;
  onLaunch: (tool: ToolKey) => void;
  onScanPc: () => void;
  scanningPc: boolean;
  scanPcError: string | null;
}

/** Ports PrimePCTuner.ps1 — the suite hub: specs + pick a tool. Specs are
 * never fetched automatically (user directive, no scan of any kind runs
 * without a button press) — Scan PC is the only trigger. */
export function HubView({
  data,
  error,
  healthWarning,
  version,
  onLaunch,
  onScanPc,
  scanningPc,
  scanPcError,
}: HubViewProps) {
  return (
    <div className={styles.page}>
      <Topbar healthWarning={healthWarning} />
      <PageHeading
        eyebrow="P C T U N E R  ·  O P E N  S O U R C E"
        headingPlain="PcTuner"
        headingAccent="Open Source"
        subtitle="Pick the tool that fits this PC — every tool shows you each change as a checkbox before anything happens. Press Scan PC to detect your system."
        size="lg"
      />

      {error && (
        <div className={styles.error}>Couldn't reach the backend: {error}</div>
      )}
      {!data && !error && <div className={styles.loading}>Loading…</div>}

      {data && (
        <>
          <div className={styles.specsRow}>
            {data.specs ? (
              <SpecsPanel specs={data.specs} />
            ) : (
              <Button
                variant="primary"
                onClick={onScanPc}
                disabled={scanningPc}
              >
                {scanningPc ? "Scanning…" : "Scan PC"}
              </Button>
            )}
            {data.specs && (
              <Button onClick={onScanPc} disabled={scanningPc}>
                {scanningPc ? "Scanning…" : "Re-scan"}
              </Button>
            )}
          </div>
          {scanPcError && (
            <div className={styles.error}>Scan failed: {scanPcError}</div>
          )}
          <div className={styles.cards}>
            {data.tools.map((tool) => (
              <ToolCard
                key={tool.Key}
                tool={tool}
                onLaunch={() => onLaunch(tool.Key)}
              />
            ))}
          </div>
        </>
      )}

      <Footer
        note={
          version
            ? `PcTuner-Open-Source hub v${version}`
            : "PcTuner-Open-Source hub"
        }
      />
    </div>
  );
}
