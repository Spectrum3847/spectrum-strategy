import type { EventEntry } from "../data/parse";
import type { EventMatch } from "../data/tbaEvent";
import type { Forecast } from "../match/outside";
import { entriesBefore } from "../match/prior";
import { redWinChance, scoutedForecast } from "../match/whatIf";

export const minMatches = 10;
export const minBand = 8;
export const offBy = 0.15;

export type Source = "tba" | "scouting";

export interface Called {
  key: string;
  red: number[];
  blue: number[];
  redScore: number;
  blueScore: number;
  redWin: number;
  predRed: number | null;
  predBlue: number | null;
}

export interface CheckRow extends Called {
  favourite: "red" | "blue";
  said: number;
  right: 0 | 0.5 | 1;
  ours: boolean;
  miss: number | null;
}

export interface Band {
  label: string;
  n: number;
  said: number;
  won: number;
}

export interface Check {
  rows: CheckRow[];
  n: number;
  enough: boolean;
  right: number;
  error: number | null;
  lean: number | null;
  bands: Band[];
  ours: CheckRow[];
  misses: CheckRow[];
}

const avg = (v: number[]) => v.reduce((a, b) => a + b, 0) / v.length;

const bands: [number, number][] = [
  [50, 60],
  [60, 70],
  [70, 80],
  [80, 90],
  [90, 101],
];

export function buildCheck(called: Called[], us: number | null): Check {
  const rows = called.map((c): CheckRow => {
    const favourite = c.redWin >= 0.5 ? "red" : "blue";
    const said = favourite === "red" ? c.redWin : 1 - c.redWin;
    const won =
      c.redScore > c.blueScore
        ? "red"
        : c.redScore < c.blueScore
          ? "blue"
          : null;
    return {
      ...c,
      favourite,
      said,
      right: won === null ? 0.5 : won === favourite ? 1 : 0,
      ours: us !== null && (c.red.includes(us) || c.blue.includes(us)),
      miss:
        c.predRed === null || c.predBlue === null
          ? null
          : Math.max(
              Math.abs(c.predRed - c.redScore),
              Math.abs(c.predBlue - c.blueScore),
            ),
    };
  });
  const errors = called.flatMap((c) =>
    c.predRed === null || c.predBlue === null
      ? []
      : [c.predRed - c.redScore, c.predBlue - c.blueScore],
  );
  return {
    rows,
    n: rows.length,
    enough: rows.length >= minMatches,
    right: rows.reduce((sum, r) => sum + r.right, 0),
    error: errors.length > 0 ? avg(errors.map(Math.abs)) : null,
    lean: errors.length > 0 ? avg(errors) : null,
    bands: bands.map(([lo, hi]) => {
      const inBand = rows.filter(
        (r) => r.said * 100 >= lo && r.said * 100 < hi,
      );
      return {
        label: `${lo}-${Math.min(hi, 100)}%`,
        n: inBand.length,
        said: inBand.length > 0 ? avg(inBand.map((r) => r.said)) : 0,
        won: inBand.length > 0 ? avg(inBand.map((r) => r.right)) : 0,
      };
    }),
    ours: rows.filter((r) => r.ours).reverse(),
    misses: rows
      .filter((r) => r.miss !== null)
      .sort((a, b) => (b.miss ?? 0) - (a.miss ?? 0))
      .slice(0, 5),
  };
}

export type Verdict =
  | "about right"
  | "too confident"
  | "too cautious"
  | "too few to tell";

export function verdict(band: Band): Verdict {
  if (band.n < minBand) return "too few to tell";
  if (Math.abs(band.won - band.said) <= offBy) return "about right";
  return band.won < band.said ? "too confident" : "too cautious";
}

const played = (m: EventMatch) => m.redScore !== null && m.blueScore !== null;

export function calledByTba(
  matches: EventMatch[],
  forecasts: Record<string, Forecast> | null,
): Called[] {
  if (!forecasts) return [];
  return matches.flatMap((m) => {
    const f = forecasts[m.key] ?? forecasts[m.key.toLowerCase()];
    if (!f || m.redScore === null || m.blueScore === null) return [];
    const hasScores = f.redScore + f.blueScore > 0;
    return [
      {
        key: m.key,
        red: m.red,
        blue: m.blue,
        redScore: m.redScore,
        blueScore: m.blueScore,
        redWin: f.redWin,
        predRed: hasScores ? f.redScore : null,
        predBlue: hasScores ? f.blueScore : null,
      },
    ];
  });
}

export function calledByScouting(
  matches: EventMatch[],
  entries: EventEntry[],
): Called[] {
  return matches.filter(played).flatMap((m) => {
    const { forecast } = scoutedForecast(
      m.red,
      m.blue,
      entriesBefore(entries, m.key),
    );
    if (!forecast || m.redScore === null || m.blueScore === null) return [];
    return [
      {
        key: m.key,
        red: m.red,
        blue: m.blue,
        redScore: m.redScore,
        blueScore: m.blueScore,
        redWin: redWinChance(forecast),
        predRed: null,
        predBlue: null,
      },
    ];
  });
}
