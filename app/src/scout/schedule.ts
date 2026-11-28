import { normalizeStation, type Values } from "./config";

export interface ScheduledMatch {
  key: string;
  compLevel: string;
  matchNumber: number;
  red: number[];
  blue: number[];
  time?: number | null;
  predictedTime?: number | null;
  redScore?: number;
  blueScore?: number;
}

export interface SavedRef {
  tbaMatchKey: string | null;
  station: string;
}

export const qualMatches = (schedule: ScheduledMatch[]) =>
  schedule.filter((m) => m.compLevel === "qm");

export function teamForStation(
  schedule: ScheduledMatch[],
  matchNumber: number | null,
  station: string,
): number | null {
  const wanted = normalizeStation(station);
  if (wanted === null || matchNumber === null) return null;
  const match = qualMatches(schedule).find(
    (m) => m.matchNumber === matchNumber,
  );
  if (!match) return null;
  const teams = wanted.startsWith("R") ? match.red : match.blue;
  return teams[Number(wanted[1]) - 1] ?? null;
}

export function stationOf(values: Values): string {
  const robot = String(values.robot ?? "").trim();
  if (robot !== "") return robot;
  for (const value of Object.values(values)) {
    if (typeof value === "object" && value !== null && !Array.isArray(value)) {
      const position = String(
        (value as Record<string, unknown>).robotPosition ?? "",
      ).trim();
      if (position !== "") return position;
    }
  }
  return "";
}

export function nextMatchNumberFor(
  station: string,
  schedule: ScheduledMatch[],
  saved: SavedRef[],
): number | null {
  const quals = qualMatches(schedule);
  if (quals.length === 0) return null;
  const wanted = normalizeStation(station);
  if (wanted === null) return null;
  const numberByKey = new Map(
    quals.map((m) => [m.key.toLowerCase(), m.matchNumber]),
  );
  const numbers = [...new Set(quals.map((m) => m.matchNumber))].sort(
    (a, b) => a - b,
  );
  const savedForStation = new Set<number>();
  const stationsByNumber = new Map<number, Set<string>>();
  for (const entry of saved) {
    const n = numberByKey.get(entry.tbaMatchKey?.toLowerCase() ?? "");
    const entryStation = normalizeStation(entry.station);
    if (n === undefined || entryStation === null) continue;
    const stations = stationsByNumber.get(n) ?? new Set<string>();
    stations.add(entryStation);
    stationsByNumber.set(n, stations);
    if (entryStation === wanted) savedForStation.add(n);
  }
  let floor: number | null = null;
  for (const [n, stations] of stationsByNumber) {
    if (
      (stations.size >= 2 || savedForStation.has(n)) &&
      (floor === null || n > floor)
    ) {
      floor = n;
    }
  }
  if (floor === null) return numbers[0] ?? null;
  const from = floor;
  return numbers.find((n) => n >= from && !savedForStation.has(n)) ?? null;
}

export function resolveMatchKey(
  typed: string,
  schedule: ScheduledMatch[],
): string | null {
  const m = /^(?:q|qm)?\s*(\d+)$/i.exec(typed.trim());
  if (!m) return null;
  const number = Number(m[1]);
  return (
    qualMatches(schedule).find((x) => x.matchNumber === number)?.key ?? null
  );
}

export interface RemoteEntry {
  id: string;
  tbaMatchKey: string | null;
  fieldValues: Values;
}

export function knownRefs(
  saved: Array<SavedRef & { id: string }>,
  remote: RemoteEntry[],
): SavedRef[] {
  const byId = new Map<string, SavedRef>();
  for (const e of remote) {
    byId.set(e.id, {
      tbaMatchKey: e.tbaMatchKey,
      station: stationOf(e.fieldValues),
    });
  }
  for (const e of saved) {
    byId.set(e.id, { tbaMatchKey: e.tbaMatchKey, station: e.station });
  }
  return [...byId.values()];
}
