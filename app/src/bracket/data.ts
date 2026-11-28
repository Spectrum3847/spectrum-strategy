import type { EventEntry } from "../data/parse";
import { canInvite, type Rounds, replayDraft } from "../picks/draft";
import { describe, incidentsByTeam } from "../picks/incidents";
import type { Layout } from "../picks/pickList";
import type { ScoutConfig } from "../scout/config";
import {
  computeStats,
  entryMatchKey,
  groupByMatch,
  mean,
  numberOf,
  sd,
} from "../team/stats";
import { model, type Strength, seeded } from "./model";

export interface Robot extends Strength {
  n: number;
  auto: number | null;
  teleop: number | null;
  climb: number | null;
  driver: number | null;
  start: string;
  incidents: string;
}
export function robotsFor(
  config: ScoutConfig,
  entries: EventEntry[],
): Map<number, Robot> {
  const grouped = new Map<number, EventEntry[]>();
  for (const e of entries)
    grouped.set(e.teamNumber, [...(grouped.get(e.teamNumber) ?? []), e]);
  const incidents = incidentsByTeam(entries),
    result = new Map<number, Robot>();
  for (const [team, mine] of grouped) {
    const inputs = mine.map((e) => ({
      id: e.id,
      matchKey: entryMatchKey(e),
      fieldValues: e.fieldValues,
    }));
    const stats = computeStats(config, inputs),
      starts = new Map<string, number>();
    const groups = groupByMatch(inputs);
    const matches = groups.flatMap((g) => {
      const samples = g.entries.flatMap(({ fieldValues: v }) => {
        const auto = numberOf(v.autoFuelScored),
          teleop = numberOf(v.teleopFuelScored);
        if (auto === null || teleop === null) return [];
        const success = (value: unknown) =>
          value === "Successful" ||
          value === "Outpost" ||
          value === "Middle" ||
          value === "Depot";
        const climb = success(v.eHigh)
          ? 30
          : success(v.eMiddle)
            ? 20
            : success(v.eLow)
              ? 10
              : 0;
        return [{ auto: auto + (success(v.auLow) ? 15 : 0), teleop, climb }];
      });
      return samples.length
        ? [
            {
              auto: mean(samples.map((x) => x.auto)),
              teleop: mean(samples.map((x) => x.teleop)),
              climb: mean(samples.map((x) => x.climb)),
            },
          ]
        : [];
    });
    const totals = matches.map((x) => x.auto + x.teleop + x.climb);
    const score = totals.length ? mean(totals) : 0;
    for (const e of mine) {
      const start = String(e.fieldValues.starting ?? "");
      if (start && start !== "No Show")
        starts.set(start, (starts.get(start) ?? 0) + 1);
    }
    const driver = stats.rows.find((row) =>
      /driver.*skill/i.test(`${row.code} ${row.label}`),
    );
    result.set(team, {
      score,
      sigma:
        totals.length > 1
          ? Math.max(1, sd(totals))
          : Math.max(10, score * 0.35),
      n: totals.length,
      auto: matches.length ? mean(matches.map((x) => x.auto)) : null,
      teleop: matches.length ? mean(matches.map((x) => x.teleop)) : null,
      climb: matches.length ? mean(matches.map((x) => x.climb)) : null,
      driver: driver?.mean ?? null,
      start: [...starts].sort((a, b) => b[1] - a[1])[0]?.[0] ?? "",
      incidents: describe(
        incidents.get(team) ?? { red: [], yellow: [], unknown: [], died: [] },
      ),
    });
  }
  return result;
}
export function report(teams: number[], robots: Map<number, Robot>) {
  const best = teams
    .filter((t) => (robots.get(t)?.n ?? 0) > 0)
    .sort((a, b) => (robots.get(b)?.score ?? 0) - (robots.get(a)?.score ?? 0))
    .slice(0, 3);
  const sum = (key: "score" | "auto" | "teleop" | "climb") => {
    const values = best
      .map((t) => robots.get(t)?.[key])
      .filter((n): n is number => n != null);
    return values.length ? values.reduce((a, b) => a + b, 0) : null;
  };
  const drivers = best
    .map((t) => robots.get(t)?.driver)
    .filter((n): n is number => n != null);
  const starts = best.map((t) => robots.get(t)?.start ?? "").filter(Boolean);
  return {
    best,
    score: sum("score"),
    auto: sum("auto"),
    teleop: sum("teleop"),
    climb: sum("climb"),
    driver: drivers.length ? mean(drivers) : null,
    clashes: [...new Set(starts.filter((s, i) => starts.indexOf(s) !== i))],
    incidents: teams
      .map((t) => [t, robots.get(t)?.incidents] as const)
      .filter(([, text]) => text),
  };
}
export function scenarios(
  ranking: number[],
  rounds: Rounds,
  us: number | null,
  layout: Layout | null,
  robots: Map<number, Robot>,
) {
  const excluded = new Set(layout?.dnp.map((x) => x.team) ?? []);
  const own = [
    ...new Set([
      ...(layout?.tiers.flatMap((x) => x.teams) ?? []),
      ...[...ranking].sort(
        (a, b) => (robots.get(b)?.score ?? 0) - (robots.get(a)?.score ?? 0),
      ),
    ]),
  ].filter((t) => !excluded.has(t));
  const kinds = [
    "Chalk",
    "Consistency first",
    "Endgame first",
    "Auto first",
    "Unpredictable A",
    "Unpredictable B",
  ];
  return kinds
    .map((name, kind) => {
      const random = seeded(kind === 4 ? 11 : 29),
        jitter = new Map(ranking.map((t) => [t, 0.85 + random() * 0.3]));
      const value = (t: number) => {
        const r = robots.get(t);
        const score = r?.score ?? 0;
        return kind === 2
          ? score + (r?.climb ?? 0)
          : kind === 3
            ? score + (r?.auto ?? 0)
            : kind >= 4
              ? score * (jitter.get(t) ?? 1)
              : kind === 1
                ? r?.n
                  ? -r.sigma
                  : Number.NEGATIVE_INFINITY
                : score;
      };
      const actions: { team: number; declined: boolean }[] = [];
      let board = replayDraft(actions, ranking, rounds);
      while (board.picking !== null) {
        const picker = board.alliances[board.picking];
        const candidates = ranking.filter((t) => canInvite(board, t));
        const choice =
          us !== null && picker?.teams.includes(us)
            ? own.find((t) => candidates.includes(t))
            : undefined;
        const team =
          choice ?? candidates.sort((a, b) => value(b) - value(a))[0];
        if (team === undefined) break;
        actions.push({ team, declined: false });
        board = replayDraft(actions, ranking, rounds);
      }
      const alliances = board.alliances.map((a) => a.teams),
        index = alliances.findIndex((a) => us !== null && a.includes(us));
      const odds =
        alliances.length === 8 && alliances.every((a) => a.length >= 3)
          ? model(alliances, robots).odds(1500).title
          : null;
      return {
        name,
        alliances,
        index,
        odds,
        chance: index >= 0 ? (odds?.[index] ?? 0) : 0,
      };
    })
    .sort(
      (a, b) =>
        Number(b.index >= 0) - Number(a.index >= 0) || b.chance - a.chance,
    );
}
