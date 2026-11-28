import { matchLabel, matchOrder, parseMatchKey } from "../data/matchKey";
import type { ScoutField, Values } from "../scout/config";
import { displayValue } from "../team/format";
import { entryMatchKey } from "../team/stats";

export interface AnswerRow {
  code: string;
  title: string;
  value: string;
  was: string | null;
}

export function answerRows(
  fields: ScoutField[],
  entry: { fieldValues: Values; rawValues: Values; corrected: string[] },
): AnswerRow[] {
  const rows: AnswerRow[] = [];
  for (const field of fields) {
    const value = displayValue(field, entry.fieldValues[field.code]);
    const fixed = entry.corrected.includes(field.code);
    if (value === "" && !fixed) continue;
    rows.push({
      code: field.code,
      title: field.title.trim() || field.code,
      value,
      was: fixed ? displayValue(field, entry.rawValues[field.code]) : null,
    });
  }
  return rows;
}

export function entryLabel(entry: {
  id: string;
  tbaMatchKey: string | null;
  fieldValues: Values;
}): string {
  const key = entryMatchKey(entry);
  if (parseMatchKey(key)) return matchLabel(key);
  return key.startsWith("typed:")
    ? `Match ${key.slice("typed:".length)} (typed)`
    : "Unplaced match";
}

const playOrder = (entry: {
  id: string;
  tbaMatchKey: string | null;
  fieldValues: Values;
}) => {
  const key = entryMatchKey(entry);
  return parseMatchKey(key) ? matchOrder(key) : -1;
};

export function newestFirst<
  T extends {
    id: string;
    tbaMatchKey: string | null;
    fieldValues: Values;
    updatedAt: string;
  },
>(entries: T[]): T[] {
  return [...entries].sort(
    (a, b) =>
      playOrder(b) - playOrder(a) || b.updatedAt.localeCompare(a.updatedAt),
  );
}
