import type { EventEntry } from "../data/parse";
import {
  activeChoices,
  allFields,
  labelForStored,
  type ScoutConfig,
  type ScoutField,
} from "../scout/config";
import {
  autoPointsOf,
  groupByMatch,
  numberOf,
  outcomes,
  type StatInput,
  type StatRow,
  type TeamStats,
} from "../team/stats";
import { roleTitle } from "../team/summary";
import type { RobotRoles } from "./brief";
import { noShow, startCounts, startField } from "./startConflicts";

export const season = {
  fuelPoints: 1,
  levelPoints: 10,
  teleopSeconds: 140,
  assumedClimbSeconds: 15,
} as const;

export const jobs = ["Score", "Feed", "Defend", "Flex"] as const;
export const noClimb = "No climb";

const defendShare = 0.3;
const defendBelow = 0.6;
const feedShare = 0.4;
const feedBelow = 0.7;
const scoreFrom = 0.7;
const minRoleMatches = 2;
const minClimbTries = 2;
const climbRate = 0.5;

export const defenseTitle = /defen[cs]e/i;
const feedTitle = /pass|feed|hoard/i;
const levelTitle = /\bL(\d)\b/i;
const climbTimeTitle = /climb.*(time|sec)|(time|sec).*climb/i;

export interface RoleCount {
  title: string;
  matches: number;
  of: number;
}

export interface LevelTally {
  level: number;
  label: string;
  made: number;
  tries: number;
}

export interface Profile {
  team: number;
  matches: number;
  scoring: number;
  teleopFuel: number;
  roles: RoleCount[];
  starts: Map<string, number>;
  autoAt: Map<string, number[]>;
  climbs: LevelTally[];
  climbSeconds: number | null;
}

export interface Choice {
  value: string;
  why: string;
}

export interface Plan {
  job: Choice;
  start: Choice | null;
  climb: Choice | null;
}

const round = (n: number) => Math.round(n);

export function startOptions(config: ScoutConfig): string[] {
  const field = startField(config);
  return field
    ? activeChoices(field)
        .map(([, label]) => label)
        .filter((label) => label.toLowerCase() !== noShow)
    : [];
}

const climbFields = (config: ScoutConfig) =>
  allFields(config)
    .flatMap((field) => {
      const level = levelTitle.exec(field.title);
      return level && field.type === "select"
        ? [{ level: Number(level[1]), field }]
        : [];
    })
    .sort((a, b) => a.level - b.level);

export function climbOptions(config: ScoutConfig): string[] {
  const levels = climbFields(config).map((c) => `L${c.level}`);
  return levels.length === 0 ? [] : [noClimb, ...levels];
}

const climbTimeField = (config: ScoutConfig): ScoutField | null =>
  allFields(config).find(
    (f) =>
      (f.type === "number" || f.type === "counter" || f.type === "range") &&
      climbTimeTitle.test(f.title),
  ) ?? null;

function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1
    ? (sorted[mid] ?? 0)
    : ((sorted[mid - 1] ?? 0) + (sorted[mid] ?? 0)) / 2;
}

function autoBySpot(
  config: ScoutConfig,
  entries: EventEntry[],
): Map<string, number[]> {
  const field = startField(config);
  const out = new Map<string, number[]>();
  if (!field) return out;
  for (const entry of entries) {
    const raw = entry.fieldValues[field.code];
    if (raw === undefined || raw === null) continue;
    const spot = labelForStored(field, raw).trim();
    const auto = autoPointsOf(config, entry.fieldValues);
    if (spot === "" || spot.toLowerCase() === noShow || auto === null) continue;
    out.set(spot, [...(out.get(spot) ?? []), auto]);
  }
  return out;
}

const minAutoSamples = 2;
const sameAutoShare = 0.2;
const sameAutoFloor = 5;

export function autoNote(p: Profile, spot: string): string {
  const here = p.autoAt.get(spot) ?? [];
  const elsewhere = [...p.autoAt]
    .filter(([s]) => s !== spot)
    .flatMap(([, values]) => values);
  if (here.length < minAutoSamples || elsewhere.length < minAutoSamples) {
    return "";
  }
  const avg = (v: number[]) => v.reduce((a, b) => a + b, 0) / v.length;
  const a = avg(here);
  const b = avg(elsewhere);
  const pair = (x: number, y: number) => `${round(x)} vs ${round(y)}`;
  if (
    Math.abs(a - b) < Math.max(sameAutoFloor, sameAutoShare * Math.max(a, b))
  ) {
    return `. Auto is about the same from other spots (${pair(a, b)}), so the spot can move`;
  }
  return a > b
    ? `. Auto is better here (${pair(a, b)} elsewhere)`
    : `. Auto is better elsewhere (${pair(b, a)} here)`;
}

export function profileOf(input: {
  config: ScoutConfig;
  team: number;
  entries: EventEntry[];
  inputs: StatInput[];
  stats: Pick<TeamStats, "matches" | "total">;
  teleop: StatRow | null;
}): Profile {
  const { config, team, entries, inputs, stats, teleop } = input;
  const groups = groupByMatch(inputs);
  const roles: RoleCount[] = [];
  for (const field of allFields(config)) {
    if (field.type !== "boolean" || !roleTitle.test(field.title)) continue;
    const found = outcomes(field, groups);
    if (!found || found.length === 0) continue;
    roles.push({
      title: field.title.trim() || field.code,
      matches: found.filter((o) => o.outcome === "positive").length,
      of: found.length,
    });
  }
  const climbs = climbFields(config).map(({ level, field }): LevelTally => {
    const found = outcomes(field, groups) ?? [];
    const made = found.filter((o) => o.outcome === "positive").length;
    const failed = found.filter((o) => o.outcome === "failed").length;
    return { level, label: `L${level}`, made, tries: made + failed };
  });
  const timeField = climbTimeField(config);
  const times = timeField
    ? inputs
        .map((i) => numberOf(i.fieldValues[timeField.code]))
        .filter((v): v is number => v !== null && v > 0)
    : [];
  return {
    team,
    matches: stats.matches,
    scoring: stats.total?.typical ?? 0,
    teleopFuel: teleop?.typical ?? 0,
    roles,
    starts: startCounts(config, entries, [team]).get(team) ?? new Map(),
    autoAt: autoBySpot(config, entries),
    climbs,
    climbSeconds: median(times),
  };
}

const roleOf = (p: Profile, title: RegExp) =>
  p.roles.find((r) => title.test(r.title)) ?? null;

const share = (r: RoleCount | null, from: number) =>
  r !== null && r.of >= minRoleMatches && r.matches / r.of >= from;

export function recommendJobs(profiles: Profile[]): Map<number, Choice> {
  const top = profiles
    .filter((p) => p.matches > 0 && p.scoring > 0)
    .reduce<Profile | null>(
      (best, p) => (best === null || p.scoring > best.scoring ? p : best),
      null,
    );
  const out = new Map<number, Choice>();
  for (const p of profiles) {
    out.set(p.team, jobFor(p, top));
  }
  return out;
}

function jobFor(p: Profile, top: Profile | null): Choice {
  if (p.matches === 0) return { value: "Flex", why: "not scouted yet" };
  if (top === null) return { value: "Flex", why: "no scoring recorded yet" };
  if (p === top) {
    return {
      value: "Score",
      why: `best scorer here, typical score ${round(p.scoring)}`,
    };
  }
  const rel = p.scoring / top.scoring;
  const against = `typical score ${round(p.scoring)} against ${round(top.scoring)}`;
  const defense = roleOf(p, defenseTitle);
  const feed = roleOf(p, feedTitle);
  if (defense && share(defense, defendShare) && rel < defendBelow) {
    return {
      value: "Defend",
      why: `played defense ${defense.matches} of ${defense.of} matches, ${against}`,
    };
  }
  if (feed && share(feed, feedShare) && rel < feedBelow) {
    return {
      value: "Feed",
      why: `${feed.title.toLowerCase()} ${feed.matches} of ${feed.of} matches, ${against}`,
    };
  }
  if (rel >= scoreFrom) {
    return { value: "Score", why: `scores close to ${top.team}, ${against}` };
  }
  return { value: "Flex", why: `${against}, no strong role in the data` };
}

export function recommendStarts(
  profiles: Profile[],
  options: string[],
): Map<number, Choice> {
  const usable = (p: Profile) =>
    [...p.starts]
      .filter(([spot]) => options.includes(spot))
      .sort((a, b) => b[1] - a[1]);
  const order = [...profiles].sort(
    (a, b) =>
      Number(usable(b).length > 0) - Number(usable(a).length > 0) ||
      b.scoring - a.scoring,
  );
  const taken = new Map<string, number>();
  const out = new Map<number, Choice>();
  for (const p of order) {
    const spots = usable(p);
    const total = spots.reduce((sum, [, n]) => sum + n, 0);
    const first = spots[0];
    const free = spots.find(([spot]) => !taken.has(spot));
    let pick: Choice;
    if (free && first) {
      pick = {
        value: free[0],
        why:
          free[0] === first[0]
            ? `usual spot, ${free[1]} of ${total} matches`
            : `${first[0]} goes to ${taken.get(first[0])}, who scores more. Next most used, ${free[1]} of ${total} matches`,
      };
    } else {
      pick = {
        value: options.find((s) => !taken.has(s)) ?? options[0] ?? "",
        why: first
          ? "their spots go to partners who score more, so a free spot"
          : "no start data, so a free spot",
      };
    }
    taken.set(pick.value, p.team);
    out.set(p.team, { ...pick, why: pick.why + autoNote(p, pick.value) });
  }
  return out;
}

export function recommendClimb(p: Profile): Choice | null {
  if (p.climbs.length === 0) return null;
  if (p.matches === 0) return { value: noClimb, why: "not scouted yet" };
  const tries = p.climbs.reduce((sum, c) => sum + c.tries, 0);
  const made = p.climbs.reduce((sum, c) => sum + c.made, 0);
  if (tries === 0) {
    return {
      value: noClimb,
      why: `never tried to climb in ${p.matches} scouted matches`,
    };
  }
  if (made === 0) {
    return { value: noClimb, why: `failed every climb, 0 of ${tries} tries` };
  }
  const usual = p.climbs.reduce((best, c) =>
    c.made > best.made || (c.made === best.made && c.level > best.level)
      ? c
      : best,
  );
  if (usual.tries < minClimbTries) {
    return {
      value: noClimb,
      why: `only ${usual.tries} try at ${usual.label}, too few to count on`,
    };
  }
  const rate = usual.made / usual.tries;
  if (rate < climbRate) {
    return {
      value: noClimb,
      why: `makes ${usual.label} only ${usual.made} of ${usual.tries} tries, so keep scoring`,
    };
  }
  const seconds = p.climbSeconds ?? season.assumedClimbSeconds;
  const lost =
    (p.teleopFuel / season.teleopSeconds) * seconds * season.fuelPoints;
  const gain = rate * usual.level * season.levelPoints;
  const assumed = p.climbSeconds === null ? " (assumed)" : "";
  const base = `${usual.label} made ${usual.made} of ${usual.tries}, worth about ${round(gain)} points. Climbing takes about ${round(seconds)}s${assumed} and costs about ${round(lost)} points of fuel`;
  return gain >= lost
    ? { value: usual.label, why: `${base}, so climb` }
    : { value: noClimb, why: `${base}, so keep scoring` };
}

export function recommendPlans(
  config: ScoutConfig,
  alliances: Profile[][],
): Map<number, Plan> {
  const options = startOptions(config);
  const out = new Map<number, Plan>();
  for (const profiles of alliances) {
    const job = recommendJobs(profiles);
    const start =
      options.length > 0 ? recommendStarts(profiles, options) : null;
    for (const p of profiles) {
      out.set(p.team, {
        job: job.get(p.team) ?? { value: "Flex", why: "" },
        start: start?.get(p.team) ?? null,
        climb: recommendClimb(p),
      });
    }
  }
  return out;
}

export const rolesLine = (p: Profile): string =>
  p.roles
    .filter((r) => r.matches > 0)
    .map((r) => `${r.title} ${r.matches}/${r.of}`)
    .join(", ");

export type OverrideKind = "job" | "start" | "climb";
export const overrideKey = {
  job: "teleop",
  start: "start",
  climb: "endgame",
} as const;

export function optionsFor(config: ScoutConfig, kind: OverrideKind): string[] {
  if (kind === "job") return [...jobs];
  return kind === "start" ? startOptions(config) : climbOptions(config);
}

export function overrideOf(
  config: ScoutConfig,
  kind: OverrideKind,
  stored: string | undefined,
): string | null {
  const text = (stored ?? "").trim().toLowerCase();
  if (text === "") return null;
  return optionsFor(config, kind).find((o) => o.toLowerCase() === text) ?? null;
}

export function withOverride(
  config: ScoutConfig,
  roles: RobotRoles,
  kind: OverrideKind,
  value: string | null,
): RobotRoles {
  const key = overrideKey[kind];
  if (value !== null) return { ...roles, [key]: value };
  if (overrideOf(config, kind, roles[key]) === null) return roles;
  const { [key]: _cleared, ...rest } = roles;
  return rest;
}

export interface Resolved {
  value: string;
  recommended: Choice;
  changed: boolean;
}

export function resolve(
  config: ScoutConfig,
  kind: OverrideKind,
  recommended: Choice,
  roles: RobotRoles,
): Resolved {
  const override = overrideOf(config, kind, roles[overrideKey[kind]]);
  const changed = override !== null && override !== recommended.value;
  return {
    value: changed ? override : recommended.value,
    recommended,
    changed,
  };
}
