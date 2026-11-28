import type { EventEntry, PitEntry } from "../data/parse";
import { allFields, labelForStored, type ScoutConfig } from "../scout/config";
import { commentsFor, type TeamComment } from "../team/format";
import { anyClimb, climbField, fuelStats } from "../team/fuel";
import {
  computeStats,
  entryMatchKey,
  groupByMatch,
  phaseStats,
  type RateRow,
} from "../team/stats";
import { buildSummary, type CommentSummary } from "../team/summary";
import {
  type Plan,
  type Profile,
  profileOf,
  recommendPlans,
  rolesLine,
} from "./recommend";

export type Side = "red" | "blue";

export interface RobotRow {
  team: number;
  side: Side;
  nickname: string;
  matches: number;
  robotType: string;
  driveCoach: string;
  auto: number | null;
  teleop: number | null;
  climb: string;
  autoClimb: boolean;
  maxAuto: number | null;
  maxTeleop: number | null;
  iqmFuel: number | null;
  thisMatch: number | null;
  epa: number | null;
  comment: TeamComment | null;
  profile: Profile;
  roles: string;
  summary: CommentSummary;
}

const driveTrainCode = "drivetrainType";
const trenchFitCode = "trenchFit";
const launcherCode = "launcherType";
const driveCoachCode = "driveCoachName";
const autoClimbCode = "auLow";

export function robotType(entry: PitEntry | null, pitConfig: ScoutConfig) {
  if (!entry) return "";
  const values = entry.fieldValues;
  const field = allFields(pitConfig).find((f) => f.code === driveTrainCode);
  const raw = values[driveTrainCode];
  const driveTrain =
    raw === undefined || raw === null
      ? ""
      : field
        ? labelForStored(field, raw)
        : String(raw).trim();
  const fit = values[trenchFitCode];
  const trench =
    fit === undefined || fit === null
      ? ""
      : fit === true || String(fit).toLowerCase() === "true"
        ? "trench"
        : "bump";
  const launcher = String(values[launcherCode] ?? "").trim();
  return [driveTrain, trench, launcher].filter((p) => p !== "").join(" · ");
}

export function climbLabel(rates: RateRow[]): string {
  let best = 0;
  for (const rate of rates) {
    const level = /\bL(\d)\b/i.exec(rate.label);
    if (level && rate.successes > 0) best = Math.max(best, Number(level[1]));
  }
  return best > 0 ? `L${best}` : "";
}

export interface RobotInput {
  config: ScoutConfig;
  pitConfig: ScoutConfig;
  matchKey: string;
  red: number[];
  blue: number[];
  entries: EventEntry[];
  pit: PitEntry[];
  nicknames: Map<number, string>;
  epa: Record<number, number> | null;
}

const newest = (a: PitEntry, b: PitEntry) =>
  b.updatedAt.localeCompare(a.updatedAt);

export function buildRobots(input: RobotInput): RobotRow[] {
  const key = input.matchKey.toLowerCase();
  const roster = [
    ...input.red.map((team) => ({ team, side: "red" as const })),
    ...input.blue.map((team) => ({ team, side: "blue" as const })),
  ];
  const wanted = new Set(roster.map((r) => r.team));
  const byTeam = new Map<number, EventEntry[]>();
  for (const entry of input.entries) {
    if (!wanted.has(entry.teamNumber)) continue;
    byTeam.set(entry.teamNumber, [
      ...(byTeam.get(entry.teamNumber) ?? []),
      entry,
    ]);
  }
  return roster.map(({ team, side }) => {
    const mine = byTeam.get(team) ?? [];
    const inputs = mine.map((e) => ({
      id: e.id,
      matchKey: entryMatchKey(e),
      fieldValues: e.fieldValues,
    }));
    const stats = computeStats(input.config, inputs);
    const phases = phaseStats(input.config, inputs);
    const fuel = fuelStats(mine);
    const profile = profileOf({
      config: input.config,
      team,
      entries: mine,
      inputs,
      stats,
      teleop: phases.teleop,
    });
    const pitEntry =
      input.pit.filter((e) => e.teamNumber === team).sort(newest)[0] ?? null;
    return {
      team,
      side,
      nickname: input.nicknames.get(team) ?? "",
      matches: stats.matches,
      robotType: robotType(pitEntry, input.pitConfig),
      driveCoach: String(pitEntry?.fieldValues[driveCoachCode] ?? "").trim(),
      auto: phases.auto?.iqm ?? null,
      teleop: phases.teleop?.iqm ?? null,
      climb: climbLabel(stats.rates),
      autoClimb: anyClimb(mine, climbField(input.config, autoClimbCode)),
      maxAuto: fuel.auto?.max ?? null,
      maxTeleop: fuel.teleop?.max ?? null,
      iqmFuel: fuel.teleop?.iqm ?? null,
      thisMatch: stats.series.find((p) => p.key === key)?.value ?? null,
      epa: input.epa?.[team] ?? null,
      comment: commentsFor(input.config, mine)[0] ?? null,
      profile,
      roles: rolesLine(profile),
      summary: buildSummary(input.config, groupByMatch(inputs), stats),
    };
  });
}

export function plansFor(
  config: ScoutConfig,
  rows: RobotRow[],
): Map<number, Plan> {
  return recommendPlans(
    config,
    (["red", "blue"] as const).map((side) =>
      rows.filter((r) => r.side === side).map((r) => r.profile),
    ),
  );
}

const onSide = (rows: RobotRow[], side: Side) =>
  rows.filter((r) => r.side === side);

export function epaTotal(rows: RobotRow[], side: Side): number | null {
  const known = onSide(rows, side).flatMap((r) =>
    r.epa === null ? [] : [r.epa],
  );
  return known.length === 0 ? null : known.reduce((a, b) => a + b, 0);
}

export function scoutedTotal(rows: RobotRow[], side: Side): number | null {
  if (!rows.some((r) => r.matches > 0)) return null;
  return onSide(rows, side).reduce(
    (sum, r) => sum + (r.auto ?? 0) + (r.teleop ?? 0),
    0,
  );
}

export interface ScoutedSide {
  total: number;
  robots: number;
  of: number;
}

export function scoutedInMatch(rows: RobotRow[], side: Side): ScoutedSide {
  const robots = onSide(rows, side);
  const seen = robots.flatMap((r) =>
    r.thisMatch === null ? [] : [r.thisMatch],
  );
  return {
    total: seen.reduce((a, b) => a + b, 0),
    robots: seen.length,
    of: robots.length,
  };
}

const one = (n: number) => n.toFixed(1);

export function factsFor(row: RobotRow): string[] {
  const facts: string[] = [];
  if (row.epa !== null) facts.push(`EPA ${one(row.epa)} points`);
  if (row.matches > 0) {
    const typical = (row.auto ?? 0) + (row.teleop ?? 0);
    facts.push(
      `Scouted in ${row.matches} match${row.matches === 1 ? "" : "es"}, typical score ${one(typical)}`,
    );
  } else {
    facts.push("Not scouted yet");
  }
  if (row.auto !== null || row.teleop !== null) {
    const part = (n: number | null) => (n === null ? "--" : one(n));
    facts.push(`Typical auto ${part(row.auto)}, teleop ${part(row.teleop)}`);
  }
  if (row.roles !== "") facts.push(`Roles: ${row.roles}`);
  if (row.robotType !== "") facts.push(`Robot type: ${row.robotType}`);
  if (row.climb !== "") facts.push(`Best endgame climb seen: ${row.climb}`);
  if (row.driveCoach !== "") facts.push(`Drive coach: ${row.driveCoach}`);
  return facts;
}
