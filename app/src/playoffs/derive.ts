import type { EventEntry, PitEntry } from "../data/parse";
import { robotType } from "../match/robots";
import type { Incidents } from "../picks/incidents";
import { allFields, labelForStored, type ScoutConfig } from "../scout/config";
import { commentsFor, type TeamComment } from "../team/format";
import {
  entryMatchKey,
  groupByMatch,
  phaseStats,
  type StatInput,
} from "../team/stats";
import { buildSummary } from "../team/summary";
import type { TeamRow } from "../teams/rows";

export function rankedTeams(rows: TeamRow[]): TeamRow[] {
  return rows
    .filter((r) => r.matches > 0)
    .sort(
      (a, b) =>
        (b.mean.total ?? Number.NEGATIVE_INFINITY) -
          (a.mean.total ?? Number.NEGATIVE_INFINITY) || a.team - b.team,
    );
}

const driveTrainCode = "drivetrainType";

export function tankTeams(pit: PitEntry[], pitConfig: ScoutConfig): number[] {
  const field = allFields(pitConfig).find((f) => f.code === driveTrainCode);
  const newest = new Map<number, PitEntry>();
  for (const entry of pit) {
    const seen = newest.get(entry.teamNumber);
    if (!seen || entry.updatedAt > seen.updatedAt) {
      newest.set(entry.teamNumber, entry);
    }
  }
  const out: number[] = [];
  for (const [team, entry] of newest) {
    const raw = entry.fieldValues[driveTrainCode];
    if (raw === undefined || raw === null) continue;
    const label = field ? labelForStored(field, raw) : String(raw);
    if (label.toLowerCase().includes("tank")) out.push(team);
  }
  return out.sort((a, b) => a - b);
}

export type CardColor = "red" | "unknown" | "yellow";

const hasCard = (i: Incidents) =>
  i.red.length + i.yellow.length + i.unknown.length > 0;

export function cardColors(
  incidents: Map<number, Incidents>,
): Map<number, CardColor> {
  const out = new Map<number, CardColor>();
  for (const [team, i] of incidents) {
    if (!hasCard(i)) continue;
    out.set(
      team,
      i.red.length > 0 ? "red" : i.unknown.length > 0 ? "unknown" : "yellow",
    );
  }
  return out;
}

export const cardedTeams = (colors: Map<number, CardColor>): number[] =>
  [...colors.keys()].sort((a, b) => a - b);

const driveCoachCode = "driveCoachName";

export interface PanelFacts {
  matches: number;
  avgAuto: number | null;
  avgTeleop: number | null;
  robotType: string;
  driveCoach: string;
  strengths: string[];
  concerns: string[];
  comments: TeamComment[];
}

export function panelFacts(
  team: number,
  input: {
    config: ScoutConfig;
    pitConfig: ScoutConfig;
    entries: EventEntry[];
    pit: PitEntry[];
  },
): PanelFacts {
  const mine = input.entries.filter((e) => e.teamNumber === team);
  const inputs: StatInput[] = mine.map((e) => ({
    id: e.id,
    matchKey: entryMatchKey(e),
    fieldValues: e.fieldValues,
  }));
  const groups = groupByMatch(inputs);
  const phases = phaseStats(input.config, inputs);
  const summary = buildSummary(input.config, groups, null);
  const newest = input.pit
    .filter((p) => p.teamNumber === team)
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))[0];
  return {
    matches: groups.length,
    avgAuto: phases.auto?.mean ?? null,
    avgTeleop: phases.teleop?.mean ?? null,
    robotType: robotType(newest ?? null, input.pitConfig),
    driveCoach: String(newest?.fieldValues[driveCoachCode] ?? "").trim(),
    strengths: summary.strengths.map((l) => l.text),
    concerns: summary.concerns.map((l) => l.text),
    comments: commentsFor(input.config, mine),
  };
}
