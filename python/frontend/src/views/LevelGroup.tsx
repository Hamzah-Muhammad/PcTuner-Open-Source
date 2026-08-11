import type { CatalogItem, ScanResult } from "../api";
import { ChecklistRow } from "./ChecklistRow";
import styles from "./LevelGroup.module.css";

interface LevelGroupProps {
  levelTitle: string | null;
  levelColor: string;
  module: string;
  items: CatalogItem[];
  checkedIds: Set<string>;
  onToggle: (id: string, checked: boolean) => void;
  results: Map<string, ScanResult>;
  scanning: boolean;
}

/** Ports the level/module group header + its rows from New-PrimeChecklistApp's loop. */
export function LevelGroup({
  levelTitle,
  levelColor,
  module,
  items,
  checkedIds,
  onToggle,
  results,
  scanning,
}: LevelGroupProps) {
  return (
    <div>
      <div className={styles.header}>
        {levelTitle && (
          <span className={styles.levelTitle} style={{ color: levelColor }}>
            {levelTitle}
          </span>
        )}
        <span className={styles.moduleLabel}>
          {module.toUpperCase()} · {items.length} ITEMS
        </span>
      </div>
      {items.map((item) => (
        <ChecklistRow
          key={item.Id}
          item={item}
          checked={checkedIds.has(item.Id)}
          onToggle={(c) => onToggle(item.Id, c)}
          result={results.get(item.Id)}
          scanning={scanning}
        />
      ))}
    </div>
  );
}
