import type { EventEntry, PitEntry } from "../data/parse";
import { incidentsByTeam } from "../picks/incidents";
import type { ScoutConfig } from "../scout/config";
import { anyClimb, climbField, fuelStats } from "../team/fuel";
import { computeStats, entryMatchKey, type StatInput } from "../team/stats";

export type FilterGroup = "can" | "job" | "trust";

export const filterGroups: { id: FilterGroup; label: string }[] = [
  { id: "can", label: "Can they do it?" },
  { id: "job", label: "What job?" },
  { id: "trust", label: "Can we trust them?" },
];

export const filterIds = [
  "trench",
  "moving",
  "l3",
  "autoclimb",
  "defense",
  "scorer",
  "passer",
  "clean",
  "consistent",
  "nopit",
] as const;
export type FilterId = (typeof filterIds)[number];

export interface FilterDef {
  id: FilterId;
  group: FilterGroup;
  label: string;
  rule: string;
  needsPit: boolean;
}

export const minTeamsForTopScorer = 4;
export const minRoleEntries = 2;
export const rolePercent = 30;
const minConsistentMatches = 3;
const maxSpreadRatio = 0.25;

export const filterDefs: FilterDef[] = [
  {
    id: "trench",
    group: "can",
    label: "Fits under trench",
    rule: "The latest pit entry says the robot fits under the trench.",
    needsPit: true,
  },
  {
    id: "moving",
    group: "can",
    label: "Shoots while moving",
    rule: "The latest pit entry says the robot scores while driving.",
    needsPit: true,
  },
  {
    id: "l3",
    group: "can",
    label: "Climbs L3",
    rule: "At least one scout entry recorded a successful L3 climb.",
    needsPit: false,
  },
  {
    id: "autoclimb",
    group: "can",
    label: "Auto climb",
    rule: "At least one scout entry recorded a successful auto climb.",
    needsPit: false,
  },
  {
    id: "defense",
    group: "job",
    label: "Plays defense",
    rule: `Defense in at least ${rolePercent}% of scout entries, from ${minRoleEntries} or more entries.`,
    needsPit: false,
  },
  {
    id: "scorer",
    group: "job",
    label: "Top scorer",
    rule: `Scouted fuel (auto plus teleop IQM) in the top quarter of teams at this event, once ${minTeamsForTopScorer} or more teams have data.`,
    needsPit: false,
  },
  {
    id: "passer",
    group: "job",
    label: "Passer",
    rule: `Passing in at least ${rolePercent}% of scout entries, from ${minRoleEntries} or more entries.`,
    needsPit: false,
  },
  {
    id: "clean",
    group: "trust",
    label: "Clean record",
    rule: "Scouted at this event with no cards and no deaths.",
    needsPit: false,
  },
  {
    id: "consistent",
    group: "trust",
    label: "Consistent",
    rule: `${minConsistentMatches} or more scouted matches and score spread within ${maxSpreadRatio * 100}% of the mean.`,
    needsPit: false,
  },
  {
    id: "nopit",
    group: "trust",
    label: "No pit data yet",
    rule: "No pit entry for this team. A to-do for the pit scouts.",
    needsPit: true,
  },
];

const autoClimbCode = "auLow";
const highClimbCode = "eHigh";
const defenseCode = "tRdefense";
const passerCode = "tRpasser";
const trenchCode = "trenchFit";
const movingCode = "shootsWhileMoving";

const isTrue = (raw: unknown) =>
  raw === true || (typeof raw === "string" && raw.toLowerCase() === "true");

function hasRole(entries: EventEntry[], code: string): boolean {
  if (entries.length < minRoleEntries) return false;
  const yes = entries.filter((e) => isTrue(e.fieldValues[code])).length;
  return yes * 100 >= entries.length * rolePercent;
}

export interface FilterResults {
  total: number;
  passing: Record<FilterId, Set<number>>;
}

export interface FilterInput {
  config: ScoutConfig;
  teams: number[];
  entries: EventEntry[];
  pit: Map<number, PitEntry>;
}

export function evaluateFilters(input: FilterInput): FilterResults {
  const roster = new Set(input.teams);
  const byTeam = new Map<number, EventEntry[]>();
  for (const entry of input.entries) {
    if (!roster.has(entry.teamNumber)) continue;
    byTeam.set(entry.teamNumber, [
      ...(byTeam.get(entry.teamNumber) ?? []),
      entry,
    ]);
  }
  const scoped = [...byTeam.values()].flat();
  const incidents = incidentsByTeam(scoped);
  const autoClimbField = climbField(input.config, autoClimbCode);
  const highClimbField = climbField(input.config, highClimbCode);

  const passing = Object.fromEntries(
    filterIds.map((id) => [id, new Set<number>()]),
  ) as Record<FilterId, Set<number>>;
  const scouted = new Map<number, number>();

  for (const team of roster) {
    const mine = byTeam.get(team) ?? [];
    const pit = input.pit.get(team);
    const stats: StatInput[] = mine.map((e) => ({
      id: e.id,
      matchKey: entryMatchKey(e),
      fieldValues: e.fieldValues,
    }));
    const computed = computeStats(input.config, stats);
    const fuel = fuelStats(mine);
    const pass = (id: FilterId, ok: boolean) => {
      if (ok) passing[id].add(team);
    };

    pass("trench", pit !== undefined && isTrue(pit.fieldValues[trenchCode]));
    pass("moving", pit !== undefined && isTrue(pit.fieldValues[movingCode]));
    pass("l3", anyClimb(mine, highClimbField));
    pass("autoclimb", anyClimb(mine, autoClimbField));
    pass("defense", hasRole(mine, defenseCode));
    pass("passer", hasRole(mine, passerCode));
    const found = incidents.get(team);
    pass(
      "clean",
      mine.length > 0 &&
        (found === undefined ||
          found.red.length +
            found.yellow.length +
            found.unknown.length +
            found.died.length ===
            0),
    );
    const total = computed.total;
    pass(
      "consistent",
      total !== null &&
        total.n >= minConsistentMatches &&
        total.mean > 0 &&
        (total.sd ?? 0) <= maxSpreadRatio * total.mean,
    );
    pass("nopit", pit === undefined);

    if (fuel.auto || fuel.teleop) {
      scouted.set(team, (fuel.auto?.iqm ?? 0) + (fuel.teleop?.iqm ?? 0));
    }
  }

  if (scouted.size >= minTeamsForTopScorer) {
    const sorted = [...scouted.values()].sort((a, b) => a - b);
    const cutoff = sorted[Math.floor(sorted.length * 0.75)] ?? 0;
    for (const [team, value] of scouted) {
      if (value >= cutoff) passing.scorer.add(team);
    }
  }
  return { total: roster.size, passing };
}

export const countOf = (results: FilterResults, id: FilterId) =>
  results.passing[id].size;

export function passes(
  results: FilterResults,
  team: number,
  active: FilterId[],
): boolean {
  return active.every((id) => results.passing[id].has(team));
}

export function parseFilters(param: string | null): FilterId[] {
  const asked = new Set((param ?? "").split(","));
  return filterIds.filter((id) => asked.has(id));
}

export const filtersParam = (active: FilterId[]) => active.join(",");
