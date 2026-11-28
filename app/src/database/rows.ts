import type { Corrected } from "../corrections/apply";
import { type EditInfo, editInfo } from "../corrections/history";
import { entryLabel } from "../corrections/rows";
import { matchOrder, parseMatchKey } from "../data/matchKey";
import type { EventEntry, FormEntry } from "../data/parse";
import { stationOfEntry } from "../export/csv";
import { entryIncidents } from "../picks/incidents";
import {
  allFields,
  type FieldType,
  type ScoutConfig,
  type ScoutField,
  type Values,
} from "../scout/config";
import { displayValue } from "../team/format";
import { entryMatchKey } from "../team/stats";
import type { EntryFlag } from "./flags";

export type Kind = "match" | "pit" | "prescout";

export interface DbRow {
  id: string;
  team: number;
  scout: string;
  authorUid: string;
  label: string;
  href: string | null;
  station: string;
  event: string;
  updatedAt: string;
  order: number;
  number: number | null;
  values: Values;
  rawValues: Values;
  corrected: string[];
  flags: EntryFlag[];
  incidents: string;
  entry: Corrected<EventEntry> | null;
}

const unplaced = Number.MAX_SAFE_INTEGER;

function placement(entry: Corrected<EventEntry>): {
  order: number;
  number: number | null;
} {
  const key = entryMatchKey(entry);
  const ref = parseMatchKey(key);
  if (ref) {
    return {
      order: matchOrder(key),
      number: ref.level === "qm" ? ref.number : null,
    };
  }
  if (key.startsWith("typed:")) {
    const n = Number.parseInt(key.slice("typed:".length), 10);
    if (Number.isFinite(n)) return { order: matchOrder(`_qm${n}`), number: n };
  }
  return { order: unplaced, number: null };
}

export function matchRows(
  entries: Corrected<EventEntry>[],
  flags: ReadonlyMap<string, EntryFlag[]> = new Map(),
): DbRow[] {
  return entries.map((entry) => ({
    id: entry.id,
    team: entry.teamNumber,
    scout: entry.scoutName.trim(),
    authorUid: entry.authorUid ?? "",
    label: entryLabel(entry),
    href:
      entry.tbaMatchKey && parseMatchKey(entry.tbaMatchKey)
        ? entry.tbaMatchKey
        : null,
    station: stationOfEntry(entry.rawValues),
    event: "",
    updatedAt: entry.updatedAt,
    ...placement(entry),
    values: entry.fieldValues,
    rawValues: entry.rawValues,
    corrected: entry.corrected,
    flags: flags.get(entry.id) ?? [],
    incidents: entryIncidents(entry.fieldValues),
    entry,
  }));
}

export function recordRows(entries: FormEntry[]): DbRow[] {
  return entries.map((entry) => ({
    id: entry.id,
    team: entry.teamNumber,
    scout: entry.scoutName,
    authorUid: entry.authorUid,
    label: "",
    href: null,
    station: "",
    event: entry.eventKey,
    updatedAt: entry.updatedAt,
    order: 0,
    number: null,
    values: entry.fieldValues,
    rawValues: entry.fieldValues,
    corrected: [],
    flags: [],
    incidents: "",
    entry: null,
  }));
}

export type SortKey = "match" | "team" | "scout" | "updated";

export interface Sort {
  key: SortKey;
  reversed: boolean;
}

export const sortKeys: Record<
  Kind,
  { key: SortKey; label: string; descending: boolean }[]
> = {
  match: [
    { key: "match", label: "Match", descending: false },
    { key: "team", label: "Team", descending: false },
    { key: "scout", label: "Scout", descending: false },
  ],
  pit: [
    { key: "team", label: "Team", descending: false },
    { key: "scout", label: "Scout", descending: false },
    { key: "updated", label: "Updated", descending: true },
  ],
  prescout: [
    { key: "team", label: "Team", descending: false },
    { key: "scout", label: "Scout", descending: false },
    { key: "updated", label: "Updated", descending: true },
  ],
};

export const defaultSort = (kind: Kind): Sort => ({
  key: sortKeys[kind][0]?.key ?? "team",
  reversed: false,
});

const byName = (a: string, b: string) =>
  a === b
    ? 0
    : a === ""
      ? 1
      : b === ""
        ? -1
        : a.localeCompare(b, undefined, { sensitivity: "base" });

const byMatch = (a: DbRow, b: DbRow) =>
  a.order - b.order ||
  a.team - b.team ||
  a.updatedAt.localeCompare(b.updatedAt);

const compare: Record<SortKey, (a: DbRow, b: DbRow) => number> = {
  match: byMatch,
  team: (a, b) => a.team - b.team || byMatch(a, b),
  scout: (a, b) => byName(a.scout, b.scout) || byMatch(a, b),
  updated: (a, b) => b.updatedAt.localeCompare(a.updatedAt) || a.team - b.team,
};

export function sortRows(rows: DbRow[], sort: Sort): DbRow[] {
  const sorted = [...rows].sort(compare[sort.key]);
  return sort.reversed ? sorted.reverse() : sorted;
}

export interface Filters {
  team: string;
  scout: string;
  from: string;
  to: string;
}

export const noFilters: Filters = { team: "", scout: "", from: "", to: "" };

const wholeNumber = (text: string): number | null => {
  const t = text.trim();
  return /^\d+$/.test(t) ? Number(t) : null;
};

export function filterRows(rows: DbRow[], filters: Filters): DbRow[] {
  const team = filters.team.trim().toLowerCase().replace(/^frc/, "");
  const from = wholeNumber(filters.from);
  const to = wholeNumber(filters.to);
  return rows.filter((row) => {
    if (team !== "" && !String(row.team).startsWith(team)) return false;
    if (filters.scout !== "" && row.scout !== filters.scout) return false;
    if (from !== null || to !== null) {
      if (row.number === null) return false;
      if (from !== null && row.number < from) return false;
      if (to !== null && row.number > to) return false;
    }
    return true;
  });
}

export function scoutNames(rows: DbRow[]): string[] {
  return [...new Set(rows.map((r) => r.scout).filter((s) => s !== ""))].sort(
    byName,
  );
}

const recordTypes: ReadonlySet<FieldType> = new Set([
  "text",
  "longText",
  "number",
  "boolean",
  "select",
  "range",
  "counter",
  "multiCounter",
  "checkboxSelect",
]);

export const recordFields = (config: ScoutConfig): ScoutField[] =>
  allFields(config).filter((f) => recordTypes.has(f.type));

export interface Cell {
  text: string;
  was: string | null;
  edit: EditInfo | null;
}

export function cellOf(field: ScoutField, row: DbRow): Cell {
  const text = displayValue(field, row.values[field.code]);
  if (!row.corrected.includes(field.code)) {
    return { text, was: null, edit: null };
  }
  const was = displayValue(field, row.rawValues[field.code]);
  return {
    text: text === "" ? "Blank" : text,
    was: was === "" ? "nothing" : was,
    edit: editInfo(row.entry?.correction ?? null, field.code),
  };
}
