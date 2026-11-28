import type { EventEntry } from "../data/parse";
import type { EventTeam, TeamRanking } from "../data/tbaEvent";
import { climbLabel } from "../match/robots";
import type { ScoutConfig } from "../scout/config";
import { formatStat } from "../team/format";
import { type Estimate, tied } from "../team/spread";
import {
  computeStats,
  entryMatchKey,
  mean,
  phaseStats,
  type Reliability,
  type SeriesPoint,
} from "../team/stats";

export interface TeamRow {
  team: number;
  nickname: string;
  listed: boolean;
  rank: number | null;
  record: string;
  epa: number | null;
  matches: number;
  total: number | null;
  totalSe: number | null;
  auto: number | null;
  autoSe: number | null;
  teleop: number | null;
  teleopSe: number | null;
  floor: number | null;
  iqm: { total: number | null; auto: number | null; teleop: number | null };
  mean: { total: number | null; auto: number | null; teleop: number | null };
  reliability: Reliability | null;
  sd: number | null;
  form: number | null;
  climb: number;
  series: SeriesPoint[];
}

export interface RowsInput {
  config: ScoutConfig;
  teams: EventTeam[];
  rankings: TeamRanking[];
  entries: EventEntry[];
  epa: Record<number, number> | null;
}

export const emptyRow = (team: number): TeamRow => ({
  team,
  nickname: "",
  listed: false,
  rank: null,
  record: "",
  epa: null,
  matches: 0,
  total: null,
  totalSe: null,
  auto: null,
  autoSe: null,
  teleop: null,
  teleopSe: null,
  floor: null,
  iqm: { total: null, auto: null, teleop: null },
  mean: { total: null, auto: null, teleop: null },
  reliability: null,
  sd: null,
  form: null,
  climb: 0,
  series: [],
});

export const signed = (n: number) =>
  n > 0 ? `+${formatStat(n)}` : formatStat(n);

export const minSpreadMatches = 3;

export const minFormMatches = 5;
export const formWindow = 3;

export const totalEstimate = (r: TeamRow): Estimate | null =>
  r.total === null ? null : { value: r.total, se: r.totalSe };

export const tiedRows = (a: TeamRow, b: TeamRow) =>
  tied(totalEstimate(a), totalEstimate(b));

export const reliableShare = (r: TeamRow) =>
  r.reliability && r.reliability.of > 0
    ? r.reliability.ok / r.reliability.of
    : null;

export const worksText = (r: TeamRow) =>
  r.reliability ? `${r.reliability.ok}/${r.reliability.of}` : null;

export function formOf(series: SeriesPoint[]): number | null {
  if (series.length < minFormMatches) return null;
  const split = series.length - formWindow;
  const values = series.map((p) => p.value);
  return mean(values.slice(split)) - mean(values.slice(0, split));
}

const climbLevel = (label: string) => Number(/^L(\d)$/.exec(label)?.[1] ?? 0);

export function buildRows(input: RowsInput): TeamRow[] {
  const byTeam = new Map<number, EventEntry[]>();
  for (const entry of input.entries) {
    if (entry.teamNumber <= 0) continue;
    byTeam.set(entry.teamNumber, [
      ...(byTeam.get(entry.teamNumber) ?? []),
      entry,
    ]);
  }
  const rankOf = new Map(input.rankings.map((r) => [r.team, r]));

  const roster = new Map<number, { nickname: string; listed: boolean }>();
  const known = input.teams.length > 0;
  for (const t of input.teams) {
    roster.set(t.number, { nickname: t.nickname, listed: true });
  }
  const extra = [
    ...byTeam.keys(),
    ...(known ? [] : input.rankings.map((r) => r.team)),
    ...(known ? [] : Object.keys(input.epa ?? {}).map(Number)),
  ];
  for (const team of extra) {
    if (!roster.has(team)) {
      roster.set(team, { nickname: "", listed: !known });
    }
  }

  return [...roster].map(([team, info]) => {
    const inputs = (byTeam.get(team) ?? []).map((e) => ({
      id: e.id,
      matchKey: entryMatchKey(e),
      fieldValues: e.fieldValues,
    }));
    const stats = computeStats(input.config, inputs);
    const phases = phaseStats(input.config, inputs);
    const ranking = rankOf.get(team);
    const epa = input.epa?.[team];
    const total = stats.total;
    return {
      team,
      nickname: info.nickname,
      listed: info.listed,
      rank: ranking?.rank ?? null,
      record: ranking
        ? `${ranking.wins}-${ranking.losses}-${ranking.ties}`
        : "",
      epa: epa !== undefined && epa > 0 ? epa : null,
      matches: stats.matches,
      total: total?.typical ?? null,
      totalSe: total?.se ?? null,
      auto: phases.auto?.typical ?? null,
      autoSe: phases.auto?.se ?? null,
      teleop: phases.teleop?.typical ?? null,
      teleopSe: phases.teleop?.se ?? null,
      floor: total?.floor ?? null,
      iqm: {
        total: total?.iqm ?? null,
        auto: phases.auto?.iqm ?? null,
        teleop: phases.teleop?.iqm ?? null,
      },
      mean: {
        total: total?.mean ?? null,
        auto: phases.auto?.mean ?? null,
        teleop: phases.teleop?.mean ?? null,
      },
      reliability: stats.reliability.of > 0 ? stats.reliability : null,
      sd: total && total.n >= minSpreadMatches ? total.sd : null,
      form: formOf(stats.series),
      climb: climbLevel(climbLabel(stats.rates)),
      series: stats.series,
    };
  });
}
