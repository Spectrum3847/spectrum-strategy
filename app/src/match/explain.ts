import { season as accuracySeason } from "../accuracy/season";
import { parseMatchKey } from "../data/matchKey";
import type { EventEntry, TrexReport } from "../data/parse";
import type { AllianceFuel } from "../data/tbaBreakdown";
import { allFields, labelForStored, type ScoutConfig } from "../scout/config";
import { commentsFor } from "../team/format";
import {
  breakdownKeys,
  entryMatchKey,
  groupByMatch,
  mean,
  numberOf,
  outcomes,
  type StatInput,
} from "../team/stats";
import { roleTitle } from "../team/summary";
import { traitLabel } from "../trex/traits";
import type { Forecast } from "./outside";
import { entriesBefore, entriesIn } from "./prior";
import { defenseTitle, season } from "./recommend";
import type { Side } from "./robots";
import { redWinChance, scoutedForecast, teamForecast } from "./whatIf";

const r0 = Math.round;
const signed = (n: number) => `${n >= 0 ? "+" : "-"}${Math.abs(r0(n))}`;
const name = (side: Side) => (side === "red" ? "Red" : "Blue");
const other = (side: Side): Side => (side === "red" ? "blue" : "red");

export const bigGap = 20;

export interface RobotForecast {
  team: number;
  side: Side;
  mean: number | null;
  sd: number | null;
  entries: number;
  epa: number | null;
}

export interface PredictionWhy {
  lines: string[];
  robots: RobotForecast[];
}

export function explainPrediction(input: {
  red: number[];
  blue: number[];
  entries: EventEntry[];
  epa: Record<number, number> | null;
  tba: Forecast | null;
}): PredictionWhy {
  const { red, blue, entries, epa, tba } = input;
  const robots: RobotForecast[] = [
    ...red.map((team) => ({ team, side: "red" as const })),
    ...blue.map((team) => ({ team, side: "blue" as const })),
  ].map(({ team, side }) => {
    const mine = entries.filter((e) => e.teamNumber === team);
    const f = teamForecast(team, mine);
    return {
      team,
      side,
      mean: f?.mean ?? null,
      sd: f?.sd ?? null,
      entries: mine.length,
      epa: epa?.[team] ?? null,
    };
  });
  const lines: string[] = [];
  const { forecast, missing } = scoutedForecast(red, blue, entries);
  let ours: number | null = null;
  if (forecast) {
    ours = redWinChance(forecast);
    const lead: Side = forecast.redMean >= forecast.blueMean ? "red" : "blue";
    const high = Math.max(forecast.redMean, forecast.blueMean);
    const low = Math.min(forecast.redMean, forecast.blueMean);
    const chance = lead === "red" ? ours : 1 - ours;
    lines.push(
      `Scouting expects ${name(lead)} to score ${r0(high)} fuel to ${r0(low)}, ${r0(high - low)} ahead. The six robots' scores vary from match to match by about ${r0(forecast.spread)} combined, and a ${r0(high - low)} lead against that spread gives ${name(lead)} a ${Math.round(chance * 100)}% chance.`,
    );
    const known = robots.filter((r) => r.mean !== null);
    const average = known.reduce((s, r) => s + (r.mean ?? 0), 0) / known.length;
    const top = [...known].sort((a, b) => (b.mean ?? 0) - (a.mean ?? 0))[0];
    if (top?.mean != null) {
      lines.push(
        `${top.team} (${top.side}) scores the most, ${r0(top.mean)} fuel a match, ${r0(top.mean - average)} above the average robot here.`,
      );
    }
    const wild = [...known].sort((a, b) => (b.sd ?? 0) - (a.sd ?? 0))[0];
    if (wild?.sd != null) {
      lines.push(
        `${wild.team} is the least predictable, varying by about ${r0(wild.sd)} fuel from match to match.`,
      );
    }
  } else {
    lines.push(
      `Scouting gives no win chance: ${missing.join(", ")} ${missing.length === 1 ? "has" : "have"} fewer than 3 scouted matches.`,
    );
  }
  if (tba) {
    const chance = Math.round(tba.redWin * 100);
    const agree =
      ours === null
        ? ""
        : ours >= 0.5 === tba.redWin >= 0.5
          ? " It agrees on the favourite."
          : " It disagrees on the favourite.";
    lines.push(`The Blue Alliance has Red at ${chance}%.${agree}`);
  }
  const sums = (side: Side) => {
    const list = robots.filter((r) => r.side === side);
    return list.every((r) => r.epa !== null)
      ? list.reduce((s, r) => s + (r.epa ?? 0), 0)
      : null;
  };
  const redEpa = sums("red");
  const blueEpa = sums("blue");
  if (redEpa !== null && blueEpa !== null) {
    lines.push(
      `Statbotics expects Red ${r0(redEpa)} points to Blue ${r0(blueEpa)}.`,
    );
  }
  return { lines, robots };
}

export interface RobotResult {
  team: number;
  forecast: number | null;
  scouted: number | null;
  delta: number | null;
  notes: string[];
  comment: { text: string; scout: string } | null;
}

export interface SideResult {
  side: Side;
  score: number;
  forecastScore: number | null;
  fuel: number | null;
  climb: number | null;
  fouls: number | null;
  foulCount: number | null;
  techFoulCount: number | null;
  rest: number | null;
  robots: RobotResult[];
  split: { miss: number; robotPart: number; unseen: number } | null;
  defenders: number[];
}

export interface TrexNote {
  team: number;
  trait: string;
  rating: number | null;
  scout: string;
  text: string;
}

export interface ResultWhy {
  headline: string;
  causes: string[];
  sides: Record<Side, SideResult>;
  trex: TrexNote[];
  video: string | null;
}

const fuelOf = (values: EventEntry["fieldValues"]): number | null => {
  const [auto, teleop] = accuracySeason.scoutCodes.map((c) =>
    numberOf(values[c]),
  );
  return auto === null && teleop === null ? null : (auto ?? 0) + (teleop ?? 0);
};

const asInput = (e: EventEntry): StatInput => ({
  id: e.id,
  matchKey: entryMatchKey(e),
  fieldValues: e.fieldValues,
});

function flagsOf(config: ScoutConfig, mine: EventEntry[]): string[] {
  const groups = groupByMatch(mine.map(asInput));
  const notes: string[] = [];
  if (breakdownKeys(config, groups).size > 0) {
    notes.push("Broke down or did not show");
  }
  for (const field of allFields(config)) {
    const title = field.title.trim() || field.code;
    if (field.type === "boolean" && roleTitle.test(title)) {
      const found = outcomes(field, groups) ?? [];
      if (found.some((o) => o.outcome === "positive")) notes.push(title);
    } else if (field.type === "select" && /card/i.test(title)) {
      for (const e of mine) {
        const found = outcomes(field, [
          { key: entryMatchKey(e), entries: [asInput(e)] },
        ]);
        const raw = e.fieldValues[field.code];
        if (found?.[0]?.outcome === "positive") {
          notes.push(labelForStored(field, raw));
        }
      }
    }
  }
  return [...new Set(notes)];
}

const playedDefense = (config: ScoutConfig, mine: EventEntry[]) => {
  const groups = groupByMatch(mine.map(asInput));
  return allFields(config).some(
    (f) =>
      f.type === "boolean" &&
      defenseTitle.test(f.title) &&
      (outcomes(f, groups) ?? []).some((o) => o.outcome === "positive"),
  );
};

export function explainResult(input: {
  config: ScoutConfig;
  matchKey: string;
  red: number[];
  blue: number[];
  redScore: number;
  blueScore: number;
  entries: EventEntry[];
  breakdown: AllianceFuel[];
  redWin: number | null;
  chanceFrom: string;
  tba: Forecast | null;
  trex: TrexReport[];
}): ResultWhy {
  const { config, matchKey, entries } = input;
  const key = matchKey.toLowerCase();
  const inMatch = entriesIn(entries, matchKey);
  const before = entriesBefore(entries, matchKey);
  const teamsOf = (side: Side) => (side === "red" ? input.red : input.blue);

  const sides = {} as Record<Side, SideResult>;
  for (const side of ["red", "blue"] as const) {
    const score = side === "red" ? input.redScore : input.blueScore;
    const row = input.breakdown.find(
      (b) => b.matchKey.toLowerCase() === key && b.alliance === side,
    );
    const robots = teamsOf(side).map((team): RobotResult => {
      const mine = inMatch.filter((e) => e.teamNumber === team);
      const seen = mine.flatMap((e) => fuelOf(e.fieldValues) ?? []);
      const scouted = seen.length > 0 ? mean(seen) : null;
      const forecast =
        teamForecast(
          team,
          before.filter((e) => e.teamNumber === team),
        )?.mean ?? null;
      const comment = commentsFor(config, mine)[0];
      return {
        team,
        forecast,
        scouted,
        delta:
          scouted !== null && forecast !== null ? scouted - forecast : null,
        notes: flagsOf(config, mine),
        comment: comment
          ? { text: comment.text, scout: comment.scoutName }
          : null,
      };
    });
    const fuel = row?.count ?? null;
    const fuelPoints = fuel === null ? null : fuel * season.fuelPoints;
    const climb = row?.climbPoints ?? null;
    const fouls = row?.foulPoints ?? null;
    const whole = robots.every((r) => r.delta !== null);
    const forecastFuel = robots.reduce((s, r) => s + (r.forecast ?? 0), 0);
    const scoutedFuel = robots.reduce((s, r) => s + (r.scouted ?? 0), 0);
    sides[side] = {
      side,
      score,
      forecastScore:
        input.tba && input.tba.redScore + input.tba.blueScore > 0
          ? side === "red"
            ? input.tba.redScore
            : input.tba.blueScore
          : null,
      fuel,
      climb,
      fouls,
      foulCount: row?.foulCount ?? null,
      techFoulCount: row?.techFoulCount ?? null,
      rest:
        fuelPoints !== null && climb !== null
          ? score - fuelPoints - climb - (fouls ?? 0)
          : null,
      robots,
      split:
        whole && fuel !== null
          ? {
              miss: fuel - forecastFuel,
              robotPart: scoutedFuel - forecastFuel,
              unseen: fuel - scoutedFuel,
            }
          : null,
      defenders: teamsOf(other(side)).filter((t) =>
        playedDefense(
          config,
          inMatch.filter((e) => e.teamNumber === t),
        ),
      ),
    };
  }

  const margin = input.redScore - input.blueScore;
  const winner: Side | null = margin > 0 ? "red" : margin < 0 ? "blue" : null;
  const favourite: Side | null =
    input.redWin === null ? null : input.redWin >= 0.5 ? "red" : "blue";
  const chance =
    input.redWin === null
      ? 0
      : Math.round(Math.max(input.redWin, 1 - input.redWin) * 100);
  let headline = "Tied.";
  if (winner) {
    headline = `${name(winner)} won by ${Math.abs(margin)}`;
    if (favourite) {
      headline +=
        favourite === winner
          ? `, as predicted (${chance}% from ${input.chanceFrom}).`
          : `, an upset (${input.chanceFrom} had ${name(favourite)} at ${chance}%).`;
    } else {
      headline += ".";
    }
  }

  const causes: { size: number; text: string }[] = [];
  for (const side of ["red", "blue"] as const) {
    const s = sides[side];
    for (const r of s.robots) {
      const broke = r.notes.find((n) => /broke down/i.test(n));
      if (r.delta === null || (Math.abs(r.delta) < bigGap && !broke)) continue;
      const flag = r.delta < 0 ? (broke ?? r.notes[0]) : undefined;
      causes.push({
        size: Math.abs(r.delta) + (broke ? bigGap : 0),
        text: `${r.team} (${side}) scored ${signed(r.delta)} fuel against its forecast${flag ? `, scouts marked: ${flag.toLowerCase()}` : ""}.`,
      });
    }
    if (s.split && Math.abs(s.split.unseen) >= bigGap) {
      causes.push({
        size: Math.abs(s.split.unseen),
        text: `${name(side)}'s official fuel was ${signed(s.split.unseen)} against what scouts counted, so ${s.split.unseen > 0 ? "scouts missed fuel" : "scouts over-counted"}.`,
      });
    }
    if (s.defenders.length > 0) {
      causes.push({
        size: bigGap / 2,
        text: `${name(side)} faced defense from ${s.defenders.join(", ")}.`,
      });
    }
  }
  causes.sort((a, b) => b.size - a.size);

  const number = parseMatchKey(matchKey);
  const trex = input.trex
    .filter(
      (r) =>
        number?.level === "qm" &&
        r.matchNumber === number.number &&
        r.report.trim() !== "",
    )
    .map((r) => ({
      team: r.teamNumber,
      trait: traitLabel(r.trait),
      rating: r.rating,
      scout: r.scoutName,
      text: r.report.trim(),
    }));

  return {
    headline,
    causes: causes.slice(0, 4).map((c) => c.text),
    sides,
    trex,
    video:
      input.breakdown.find(
        (b) => b.matchKey.toLowerCase() === key && b.video !== undefined,
      )?.video ?? null,
  };
}
