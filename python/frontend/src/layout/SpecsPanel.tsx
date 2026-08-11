import type { PCSpecs } from "../api";
import { Chip } from "../primitives/Chip";
import styles from "./SpecsPanel.module.css";

interface SpecsPanelProps {
  specs: PCSpecs;
}

/** Ports Add-PrimeSpecChips. */
export function SpecsPanel({ specs }: SpecsPanelProps) {
  const session = specs.Elevated
    ? "Administrator"
    : "NOT elevated — some checks limited";
  return (
    <div className={styles.panel}>
      <Chip label="CPU" value={`${specs.CPU}  [${specs.Cores}]`} />
      <Chip label="GPU" value={specs.GPU} />
      <Chip label="RAM" value={specs.RAM} />
      <Chip label="OS" value={specs.OS} />
      <Chip label="Disks" value={specs.Disks} />
      <Chip label="NIC" value={specs.NIC} />
      <Chip
        label="Session"
        value={session}
        valueColor={specs.Elevated ? undefined : "var(--red)"}
      />
    </div>
  );
}
