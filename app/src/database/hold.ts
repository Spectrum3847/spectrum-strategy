import type { DbRow } from "./rows";

export function heldRows(
  rows: DbRow[],
  held: ReadonlySet<string> | null,
): { shown: DbRow[]; waiting: number } {
  if (held === null) return { shown: rows, waiting: 0 };
  const shown = rows.filter((r) => held.has(r.id));
  return { shown, waiting: rows.length - shown.length };
}

export const holdIds = (rows: DbRow[]): Set<string> =>
  new Set(rows.map((r) => r.id));
