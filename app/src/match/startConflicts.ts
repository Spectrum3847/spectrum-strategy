import type { EventEntry } from "../data/parse";
import {
  allFields,
  labelForStored,
  type ScoutConfig,
  type ScoutField,
} from "../scout/config";

export const noShow = "no show";
const minEntries = 2;

export interface UsualStart {
  team: number;
  position: string;
  count: number;
  total: number;
}

export interface StartConflict {
  position: string;
  starts: UsualStart[];
}

export const startField = (config: ScoutConfig): ScoutField | null =>
  allFields(config).find(
    (f) => f.type === "select" && /\bstart/i.test(f.title),
  ) ?? null;

export function startCounts(
  config: ScoutConfig,
  entries: EventEntry[],
  teams: number[],
): Map<number, Map<string, number>> {
  const field = startField(config);
  const wanted = new Set(teams);
  const byTeam = new Map<number, Map<string, number>>();
  if (!field) return byTeam;
  for (const entry of entries) {
    if (!wanted.has(entry.teamNumber)) continue;
    const raw = entry.fieldValues[field.code];
    if (raw === undefined || raw === null) continue;
    const label = labelForStored(field, raw).trim();
    if (label === "" || label.toLowerCase() === noShow) continue;
    const counts = byTeam.get(entry.teamNumber) ?? new Map<string, number>();
    counts.set(label, (counts.get(label) ?? 0) + 1);
    byTeam.set(entry.teamNumber, counts);
  }
  return byTeam;
}

export function usualStarts(
  config: ScoutConfig,
  entries: EventEntry[],
  teams: number[],
): Map<number, UsualStart> {
  const out = new Map<number, UsualStart>();
  for (const [team, counts] of startCounts(config, entries, teams)) {
    const total = [...counts.values()].reduce((a, b) => a + b, 0);
    if (total < minEntries) continue;
    let top: [string, number] | null = null;
    for (const found of counts) {
      if (top === null || found[1] > top[1]) top = found;
    }
    if (top === null || top[1] * 2 <= total) continue;
    out.set(team, { team, position: top[0], count: top[1], total });
  }
  return out;
}

export function startConflicts(
  alliance: number[],
  usual: Map<number, UsualStart>,
): StartConflict[] {
  const byPosition = new Map<string, UsualStart[]>();
  for (const team of alliance) {
    const start = usual.get(team);
    if (!start) continue;
    byPosition.set(start.position, [
      ...(byPosition.get(start.position) ?? []),
      start,
    ]);
  }
  return [...byPosition]
    .filter(([, starts]) => starts.length > 1)
    .map(([position, starts]) => ({ position, starts }));
}

export function conflictMessage(conflict: StartConflict): string {
  const teams = conflict.starts.map((s) => String(s.team));
  const last = teams[teams.length - 1];
  const names =
    teams.length === 2
      ? `${teams[0]} and ${last}`
      : `${teams.slice(0, -1).join(", ")} and ${last}`;
  const counts = conflict.starts.map((s) => `${s.count}/${s.total}`).join(", ");
  return `${names} ${teams.length === 2 ? "both" : "all"} usually start ${conflict.position} (${counts})`;
}
