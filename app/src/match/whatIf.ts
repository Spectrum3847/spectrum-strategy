import type { EventEntry } from "../data/parse";
import { parseTeamNumber } from "../now/myTeam";
import { fuelStats } from "../team/fuel";

export const minEntriesPerTeam = 3;
const minProbability = 0.01;
const maxProbability = 0.99;

export function normalCdf(z: number): number {
  const x = Math.abs(z) / Math.SQRT2;
  const t = 1 / (1 + 0.3275911 * x);
  const poly =
    t *
    (0.254829592 +
      t *
        (-0.284496736 +
          t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))));
  const erf = 1 - poly * Math.exp(-x * x);
  return z >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
}

export interface WinChance {
  red: number | null;
  missing: number[];
}

export interface TeamForecast {
  team: number;
  mean: number;
  sd: number;
  entries: number;
}

export interface ScoutedForecast {
  red: TeamForecast[];
  blue: TeamForecast[];
  redMean: number;
  blueMean: number;
  spread: number;
}

export function teamForecast(
  team: number,
  mine: EventEntry[],
): TeamForecast | null {
  const { auto, teleop } = fuelStats(mine);
  if (
    !auto ||
    !teleop ||
    auto.n < minEntriesPerTeam ||
    teleop.n < minEntriesPerTeam ||
    auto.sd === null ||
    teleop.sd === null
  ) {
    return null;
  }
  return {
    team,
    mean: auto.mean + teleop.mean,
    sd: Math.sqrt(auto.sd ** 2 + teleop.sd ** 2),
    entries: Math.min(auto.n, teleop.n),
  };
}

export function scoutedForecast(
  red: number[],
  blue: number[],
  entries: EventEntry[],
): { forecast: ScoutedForecast | null; missing: number[] } {
  const wanted = new Set([...red, ...blue]);
  const byTeam = new Map<number, EventEntry[]>();
  for (const entry of entries) {
    if (!wanted.has(entry.teamNumber)) continue;
    byTeam.set(entry.teamNumber, [
      ...(byTeam.get(entry.teamNumber) ?? []),
      entry,
    ]);
  }
  const forecasts = new Map<number, TeamForecast | null>(
    [...wanted].map((t) => [t, teamForecast(t, byTeam.get(t) ?? [])]),
  );
  const missing = [...red, ...blue].filter((t) => forecasts.get(t) === null);
  if (missing.length > 0) return { forecast: null, missing };
  const of = (teams: number[]) => teams.flatMap((t) => forecasts.get(t) ?? []);
  const r = of(red);
  const b = of(blue);
  const sum = (list: TeamForecast[], pick: (f: TeamForecast) => number) =>
    list.reduce((total, f) => total + pick(f), 0);
  return {
    forecast: {
      red: r,
      blue: b,
      redMean: sum(r, (f) => f.mean),
      blueMean: sum(b, (f) => f.mean),
      spread: Math.sqrt(sum([...r, ...b], (f) => f.sd ** 2)),
    },
    missing: [],
  };
}

export function redWinChance(f: ScoutedForecast): number {
  const diff = f.redMean - f.blueMean;
  const raw =
    f.spread === 0
      ? diff > 0
        ? 1
        : diff < 0
          ? 0
          : 0.5
      : normalCdf(diff / f.spread);
  return Math.min(maxProbability, Math.max(minProbability, raw));
}

export function scoutedWinChance(
  red: number[],
  blue: number[],
  entries: EventEntry[],
): WinChance {
  const { forecast, missing } = scoutedForecast(red, blue, entries);
  return forecast
    ? { red: redWinChance(forecast), missing: [] }
    : { red: null, missing };
}

export function parseSlots(slots: string[]): (number | null)[] {
  return slots.map((s) => parseTeamNumber(s));
}

export function readyTeams(
  slots: string[],
): { red: number[]; blue: number[] } | null {
  const teams = parseSlots(slots);
  if (teams.length !== 6 || teams.some((t) => t === null)) return null;
  const nums = teams as number[];
  return { red: nums.slice(0, 3), blue: nums.slice(3) };
}
