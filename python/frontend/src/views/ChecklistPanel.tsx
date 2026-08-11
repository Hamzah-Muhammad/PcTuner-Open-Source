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
      {groups.map((g, i) => {
        const meta = levelMeta[g.level] ?? {
          title: `LEVEL ${g.level}`,
          color: "var(--muted)",
        };
        // Only show the level title where the level actually changes from
        // the previous group — Startup Optimizer has two modules sharing
        // Level 1 ("Registry Run Entries", "Startup Folder Shortcuts"),
        // which otherwise renders as two consecutive groups with the exact
        // same "STARTUP APPS" label, reading like an accidental repeat
        // rather than two distinct sections.
        const showLevelTitle = i === 0 || groups[i - 1].level !== g.level;
        return (
          <LevelGroup
            key={`${g.level}|${g.module}`}
            levelTitle={showLevelTitle ? meta.title : null}
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
