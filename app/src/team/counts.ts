import {
  allFields,
  labelForStored,
  type ScoutConfig,
  type ScoutField,
  selectedKeys,
} from "../scout/config";
import type { MatchGroup } from "./stats";

export interface ValueCount {
  label: string;
  count: number;
}

export interface CountRow {
  code: string;
  label: string;
  counts: ValueCount[];
}

const startField = /start/i;

const counted = (field: ScoutField) =>
  field.type === "checkboxSelect" ||
  (field.type === "select" && startField.test(`${field.title} ${field.code}`));

const answered = (field: ScoutField, raw: unknown): string[] => {
  if (field.type === "checkboxSelect") return selectedKeys(raw);
  const stored = raw === undefined || raw === null ? "" : String(raw).trim();
  return stored === "" ? [] : [stored];
};

function matchValues(field: ScoutField, group: MatchGroup): string[] {
  const per = group.entries.map((e) =>
    answered(field, e.fieldValues[field.code]),
  );
  if (field.type === "checkboxSelect") return [...new Set(per.flat())];
  const votes = new Map<string, number>();
  for (const [value] of per) {
    if (value !== undefined) votes.set(value, (votes.get(value) ?? 0) + 1);
  }
  let best: string | null = null;
  for (const [value, n] of votes) {
    if (best === null || n > (votes.get(best) ?? 0)) best = value;
  }
  return best === null ? [] : [best];
}

export function valueCounts(
  config: ScoutConfig,
  groups: MatchGroup[],
): CountRow[] {
  const rows: CountRow[] = [];
  for (const field of allFields(config).filter(counted)) {
    const tally = new Map<string, number>();
    for (const group of groups) {
      for (const value of matchValues(field, group)) {
        tally.set(value, (tally.get(value) ?? 0) + 1);
      }
    }
    if (tally.size === 0) continue;
    const order = (key: string) => {
      const at = field.choices?.findIndex(([k]) => k === key) ?? -1;
      return at < 0 ? Number.MAX_SAFE_INTEGER : at;
    };
    const counts = [...tally]
      .sort((a, b) => b[1] - a[1] || order(a[0]) - order(b[0]))
      .map(([key, count]) => ({
        label:
          field.type === "checkboxSelect"
            ? (field.choices?.find(([k]) => k === key)?.[1] ?? key)
            : labelForStored(field, key),
        count,
      }));
    rows.push({
      code: field.code,
      label: field.title.trim() || field.code,
      counts,
    });
  }
  return rows;
}
