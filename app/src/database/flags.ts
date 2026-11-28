import { matchLabel } from "../data/matchKey";
import type { EventEntry } from "../data/parse";
import { stationOfEntry } from "../export/csv";
import { entryMatchKey } from "../team/stats";

export type FlagKind = "team" | "station" | "match";

export interface EntryFlag {
  kind: FlagKind;
  reason: string;
}

export const flagLabel: Record<FlagKind, string> = {
  team: "Same team",
  station: "Same station",
  match: "Match number",
};

const severity: FlagKind[] = ["team", "station", "match"];

const aliases: Record<string, string> = {
  qm: "qm",
  q: "qm",
  qual: "qm",
  quals: "qm",
  qualification: "qm",
  match: "qm",
  m: "qm",
};

export function parseMatchNumber(
  raw: string,
): { level: string | null; number: number } | null {
  const text = raw.trim().toLowerCase();
  if (text === "") return null;
  const tail = (text.includes("_") ? text.split("_").pop() : text) ?? "";
  const compact = tail.replaceAll(" ", "");
  const withLevel = /^([a-z]+)(\d+)(?:m(\d+))?$/.exec(compact);
  if (withLevel) {
    const number = Number.parseInt(withLevel[3] ?? withLevel[2] ?? "", 10);
    if (Number.isFinite(number)) {
      const level = withLevel[1] ?? "";
      return { level: aliases[level] ?? level, number };
    }
  }
  if (/^\d+$/.test(compact)) return { level: null, number: Number(compact) };
  return null;
}

function typedNumber(entry: EventEntry): number | null {
  const typed = entry.fieldValues.matchNumber;
  if (typeof typed === "number") return Math.trunc(typed);
  if (typeof typed === "string") return parseMatchNumber(typed)?.number ?? null;
  return null;
}

function matchProblem(
  entry: EventEntry,
  scheduled: Set<number>,
): string | null {
  const typed = typedNumber(entry);
  if (typed === null) return null;
  const key = entry.tbaMatchKey?.trim() ?? "";
  if (key !== "") {
    const fromKey = parseMatchNumber(key)?.number;
    if (fromKey === undefined || fromKey === typed) return null;
    return `Scouted as match ${typed}, but saved against ${matchLabel(key)}.`;
  }
  if (scheduled.size === 0 || scheduled.has(typed)) return null;
  return `Match ${typed} is not in the loaded schedule.`;
}

export function detectFlags(
  entries: EventEntry[],
  scheduledNumbers: Iterable<number> = [],
): Map<string, EntryFlag[]> {
  const scheduled = new Set(scheduledNumbers);
  const byMatch = new Map<string, EventEntry[]>();
  for (const entry of entries) {
    const key = entryMatchKey(entry);
    byMatch.set(key, [...(byMatch.get(key) ?? []), entry]);
  }
  const found = new Map<string, EntryFlag[]>();
  const flag = (entry: EventEntry, kind: FlagKind, reason: string) =>
    found.set(entry.id, [...(found.get(entry.id) ?? []), { kind, reason }]);

  for (const [key, group] of byMatch) {
    const label = key.startsWith("typed:")
      ? `match ${key.slice("typed:".length)}`
      : matchLabel(key);
    const teams = new Map<number, EventEntry[]>();
    const stations = new Map<string, EventEntry[]>();
    for (const entry of group) {
      if (entry.teamNumber > 0) {
        teams.set(entry.teamNumber, [
          ...(teams.get(entry.teamNumber) ?? []),
          entry,
        ]);
      }
      const station = stationOfEntry(entry.fieldValues);
      if (station !== "") {
        stations.set(station, [...(stations.get(station) ?? []), entry]);
      }
    }
    for (const [team, rows] of teams) {
      if (rows.length < 2) continue;
      for (const row of rows) {
        flag(
          row,
          "team",
          `Team ${team} is on ${rows.length} rows in ${label}.`,
        );
      }
    }
    for (const [station, rows] of stations) {
      if (rows.length < 2) continue;
      for (const row of rows) {
        flag(
          row,
          "station",
          `Driver station ${station} is on ${rows.length} rows in ${label}.`,
        );
      }
    }
  }
  for (const entry of entries) {
    const problem = matchProblem(entry, scheduled);
    if (problem !== null) flag(entry, "match", problem);
  }
  for (const list of found.values()) {
    list.sort((a, b) => severity.indexOf(a.kind) - severity.indexOf(b.kind));
  }
  return found;
}
