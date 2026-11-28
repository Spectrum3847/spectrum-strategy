import type { EventEntry, PitEntry } from "../data/parse";
import type { TeamRanking } from "../data/tbaEvent";
import { robotType } from "../match/robots";
import { allFields, type ScoutConfig } from "../scout/config";
import { formatStat } from "../team/format";
import { tied } from "../team/spread";
import {
  computeStats,
  entryMatchKey,
  groupByMatch,
  outcomes,
  phaseStats,
} from "../team/stats";
import { type Incidents, incidentsByTeam } from "./incidents";

export interface TeamFacts {
  mean: number | null;
  typical: number | null;
  se: number | null;
  n: number;
  rank: number | null;
  epa: number | null;
  robotType: string;
  incidents: Incidents | null;
  auto?: number | null;
  l3?: { attempts: number; successes: number };
  defender?: boolean;
}

export interface FactsInput {
  config: ScoutConfig;
  pitConfig: ScoutConfig;
  entries: EventEntry[];
  pit: PitEntry[];
  rankings: TeamRanking[];
  epa: Record<number, number> | null;
}

const newest = (a: PitEntry, b: PitEntry) =>
  b.updatedAt.localeCompare(a.updatedAt);

export function buildFacts(input: FactsInput): Map<number, TeamFacts> {
  const byTeam = new Map<number, EventEntry[]>();
  for (const entry of input.entries) {
    byTeam.set(entry.teamNumber, [
      ...(byTeam.get(entry.teamNumber) ?? []),
      entry,
    ]);
  }
  const pitBy = new Map<number, PitEntry>();
  for (const entry of [...input.pit].sort(newest).reverse()) {
    pitBy.set(entry.teamNumber, entry);
  }
  const rank = new Map(input.rankings.map((r) => [r.team, r.rank]));
  const incidents = incidentsByTeam(input.entries);

  const out = new Map<number, TeamFacts>();
  const teams = new Set([
    ...byTeam.keys(),
    ...pitBy.keys(),
    ...rank.keys(),
    ...Object.keys(input.epa ?? {}).map(Number),
  ]);
  for (const team of teams) {
    const stats = computeStats(
      input.config,
      (byTeam.get(team) ?? []).map((e) => ({
        id: e.id,
        matchKey: entryMatchKey(e),
        fieldValues: e.fieldValues,
      })),
    );
    const inputs = (byTeam.get(team) ?? []).map((e) => ({
      id: e.id,
      matchKey: entryMatchKey(e),
      fieldValues: e.fieldValues,
    }));
    const groups = groupByMatch(inputs);
    const fields = allFields(input.config);
    const climb = fields.find((f) => f.code === "eHigh");
    const climbs = climb ? (outcomes(climb, groups) ?? []) : [];
    const defense = fields.filter((f) => /defen[cs]e/i.test(f.title));
    out.set(team, {
      auto: phaseStats(input.config, inputs).auto?.mean ?? null,
      l3: {
        attempts: climbs.filter((c) => c.outcome !== "none").length,
        successes: climbs.filter((c) => c.outcome === "positive").length,
      },
      defender: defense.some((f) =>
        (outcomes(f, groups) ?? []).some((o) => o.outcome === "positive"),
      ),
      mean: stats.total?.mean ?? null,
      typical: stats.total?.typical ?? null,
      se: stats.total?.se ?? null,
      n: stats.total?.typicalN ?? 0,
      rank: rank.get(team) ?? null,
      epa: input.epa?.[team] ?? null,
      robotType: robotType(pitBy.get(team) ?? null, input.pitConfig),
      incidents: incidents.get(team) ?? null,
    });
  }
  return out;
}

export const noFacts: TeamFacts = {
  mean: null,
  typical: null,
  se: null,
  n: 0,
  rank: null,
  epa: null,
  robotType: "",
  incidents: null,
};

export function tiedWithAbove(
  order: number[],
  facts: Map<number, TeamFacts>,
): Map<number, number> {
  const out = new Map<number, number>();
  const estimate = (team: number) => {
    const f = facts.get(team);
    return f && f.typical !== null ? { value: f.typical, se: f.se } : null;
  };
  for (let i = 1; i < order.length; i++) {
    const team = order[i];
    const above = order[i - 1];
    if (team === undefined || above === undefined) continue;
    if (tied(estimate(team), estimate(above))) out.set(team, above);
  }
  return out;
}

export function statLine(f: TeamFacts): string {
  return [
    f.typical !== null
      ? `Score ${formatStat(f.typical)}${f.se !== null ? ` ±${formatStat(f.se)}` : ""} (n=${f.n})`
      : "Not scouted",
    f.rank !== null ? `Rank ${f.rank}` : "",
    f.epa !== null && f.epa > 0 ? `EPA ${formatStat(f.epa)}` : "",
  ]
    .filter((p) => p !== "")
    .join(" · ");
}
