import { useMemo } from "react";
import type { CatalogItem, ScanResult } from "../api";
import { LevelGroup } from "./LevelGroup";
import styles from "./ChecklistPanel.module.css";

export interface LevelMeta {
  title: string;
  color: string;
}

interface ChecklistPanelProps {
  items: CatalogItem[];
  levelMeta: Record<number, LevelMeta>;
  checkedIds: Set<string>;
  onToggle: (id: string, checked: boolean) => void;
  results: Map<string, ScanResult>;
  scanning: boolean;
}

/** Ports the ScrollViewer + checklist-rows loop (grouped by Level|Module) from
 * New-PrimeChecklistApp. Scan is a single blocking call (§6.6's "ship the
 * regression" decision) — a sticky overlay covers the panel while in
 * flight, rather than flipping each row live as the WPF app does. */
export function ChecklistPanel({
  items,
  levelMeta,
  checkedIds,
  onToggle,
  results,
  scanning,
}: ChecklistPanelProps) {
  const groups = useMemo(() => {
    const order: string[] = [];
    const byKey = new Map<
      string,
      { level: number; module: string; items: CatalogItem[] }
    >();
    for (const item of items) {
      const key = `${item.Level}|${item.Module}`;
      if (!byKey.has(key)) {
        byKey.set(key, { level: item.Level, module: item.Module, items: [] });
        order.push(key);
      }
      byKey.get(key)!.items.push(item);
    }
    return order.map((k) => byKey.get(k)!);
  }, [items]);

  return (
    <div className={styles.panel}>
      {scanning && (
        <div className={styles.overlay}>
          <span className={styles.spinner} />
          Scanning… up to ~2 min
        </div>
      )}
      {groups.map((g) => {
        const meta = levelMeta[g.level] ?? {
          title: `LEVEL ${g.level}`,
          color: "var(--muted)",
        };
        return (
          <LevelGroup
            key={`${g.level}|${g.module}`}
            levelTitle={meta.title}
            levelColor={meta.color}
            module={g.module}
            items={g.items}
            checkedIds={checkedIds}
            onToggle={onToggle}
            results={results}
            scanning={scanning}
          />
        );
      })}
    </div>
  );
}
