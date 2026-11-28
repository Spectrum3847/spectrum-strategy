import { matchOrder } from "../data/matchKey";
import type { AllianceFuel } from "../data/tbaBreakdown";
import type { Values } from "../scout/config";
import { season } from "./season";

export const lambda = 1;
export const minRobots = 6;
export const okLimit = 4;
export const checkInLimit = 12;

export type Band = "ok" | "check-in" | "coach";

export const bandLabel: Record<Band, string> = {
  ok: "OK",
  "check-in": "Check in",
  coach: "Coach",
};

export function bandOf(miss: number): Band {
  const size = Math.abs(miss);
  if (size <= okLimit) return "ok";
  if (size <= checkInLimit) return "check-in";
  return "coach";
}

export function formatMiss(miss: number): string {
  const rounded = Math.round(miss * 10) / 10;
  if (rounded === 0) return "0.0";
  return `${rounded > 0 ? "+" : "-"}${Math.abs(rounded).toFixed(1)}`;
}

export interface AccuracyEntry {
  tbaMatchKey: string | null;
  teamNumber: number;
  rawValues: Values;
  scoutedByName?: string;
  authorDisplayName?: string;
  scouterUid?: string;
  addedManually?: boolean;
}

export const normalizeName = (raw: string) => raw.trim().replace(/\s+/g, " ");

export function scoutOf(entry: AccuracyEntry): string | null {
  const typed = entry.rawValues[season.scouterCode];
  const candidates = [
    entry.scoutedByName,
    typeof typed === "string" || typeof typed === "number"
      ? String(typed)
      : undefined,
    entry.authorDisplayName,
    entry.scouterUid,
  ];
  for (const candidate of candidates) {
    const name = normalizeName(candidate ?? "");
    if (name !== "") return name;
  }
  return null;
}

function numberOf(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export function countOf(entry: AccuracyEntry): number | null {
  const raw = season.scoutCodes.map((code) => entry.rawValues[code]);
  if (raw.every((v) => v === null || v === undefined)) return null;
  let total = 0;
  for (const value of raw) {
    if (value === null || value === undefined) continue;
    const n = numberOf(value);
    if (n === null) return null;
    total += n;
  }
  return total;
}

export interface Used {
  matchKey: string;
  alliance: "red" | "blue";
  team: number;
  count: number;
  official: number;
  scouted: number;
}

export interface ScoutScore {
  name: string;
  miss: number;
  robots: number;
  enough: boolean;
  band: Band;
  used: Used[];
}

export interface AccuracyReport {
  scouts: ScoutScore[];
  equations: number;
  skipped: number;
  incomplete: number;
  averageCapture: number | null;
}

export const emptyReport: AccuracyReport = {
  scouts: [],
  equations: 0,
  skipped: 0,
  incomplete: 0,
  averageCapture: null,
};

interface Equation {
  official: number;
  scouted: number;
  parts: { scout: string; used: Used }[];
}

export function solveRidge(
  rows: number[][],
  errors: number[],
  scoutCount: number,
  weight = lambda,
): number[] {
  const n = scoutCount;
  const m = Array.from({ length: n }, () => new Array<number>(n + 1).fill(0));
  const cell = (r: number, c: number) => (m[r] as number[])[c] as number;
  const add = (r: number, c: number, by: number) => {
    (m[r] as number[])[c] = cell(r, c) + by;
  };
  rows.forEach((row, r) => {
    for (const i of row) {
      add(i, n, errors[r] as number);
      for (const j of row) add(i, j, 1);
    }
  });
  for (let i = 0; i < n; i++) add(i, i, weight);

  for (let col = 0; col < n; col++) {
    let pivot = col;
    for (let r = col + 1; r < n; r++) {
      if (Math.abs(cell(r, col)) > Math.abs(cell(pivot, col))) pivot = r;
    }
    if (Math.abs(cell(pivot, col)) < 1e-12) continue;
    const swap = m[col] as number[];
    m[col] = m[pivot] as number[];
    m[pivot] = swap;
    for (let r = col + 1; r < n; r++) {
      const factor = cell(r, col) / cell(col, col);
      if (factor === 0) continue;
      for (let c = col; c <= n; c++) add(r, c, -factor * cell(col, c));
    }
  }
  const solution = new Array<number>(n).fill(0);
  for (let i = n - 1; i >= 0; i--) {
    if (Math.abs(cell(i, i)) < 1e-12) continue;
    let sum = cell(i, n);
    for (let j = i + 1; j < n; j++) sum -= cell(i, j) * (solution[j] as number);
    solution[i] = sum / cell(i, i);
  }
  return solution;
}

const byCode = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

function commonest(spellings: Map<string, number>): string {
  const names = [...spellings.entries()].sort(
    (a, b) => b[1] - a[1] || byCode(a[0], b[0]),
  );
  return names[0]?.[0] ?? "";
}

export function buildReport(
  entries: AccuracyEntry[],
  official: AllianceFuel[],
): AccuracyReport {
  const byMatch = new Map<string, AccuracyEntry[]>();
  for (const entry of entries) {
    const key = entry.tbaMatchKey?.trim().toLowerCase() ?? "";
    if (key === "" || entry.addedManually) continue;
    byMatch.set(key, [...(byMatch.get(key) ?? []), entry]);
  }

  const equations: Equation[] = [];
  let skipped = 0;
  let incomplete = 0;
  for (const alliance of official) {
    const inMatch = byMatch.get(alliance.matchKey.toLowerCase()) ?? [];
    const picked: AccuracyEntry[] = [];
    let duplicate = false;
    let missing = alliance.teams.length !== 3;
    for (const team of alliance.teams) {
      const forTeam = inMatch.filter((e) => e.teamNumber === team);
      if (forTeam.length > 1) duplicate = true;
      if (forTeam.length === 0) missing = true;
      if (forTeam.length === 1) picked.push(forTeam[0] as AccuracyEntry);
    }
    if (missing) {
      incomplete++;
      continue;
    }
    if (duplicate) {
      skipped++;
      continue;
    }
    const equation = buildEquation(alliance, picked);
    if (equation) equations.push(equation);
    else skipped++;
  }
  if (equations.length === 0) return { ...emptyReport, skipped, incomplete };
  return report(equations, skipped, incomplete);
}

function buildEquation(
  alliance: AllianceFuel,
  entries: AccuracyEntry[],
): Equation | null {
  const counts: { scout: string; team: number; count: number }[] = [];
  for (const [i, entry] of entries.entries()) {
    const scout = scoutOf(entry);
    const count = countOf(entry);
    if (scout === null || count === null) return null;
    counts.push({ scout, team: alliance.teams[i] as number, count });
  }
  const scouted = counts.reduce((sum, c) => sum + c.count, 0);
  return {
    official: alliance.count,
    scouted,
    parts: counts.map((c) => ({
      scout: c.scout,
      used: {
        matchKey: alliance.matchKey,
        alliance: alliance.alliance,
        team: c.team,
        count: c.count,
        official: alliance.count,
        scouted,
      },
    })),
  };
}

function report(
  equations: Equation[],
  skipped: number,
  incomplete: number,
): AccuracyReport {
  const indexByKey = new Map<string, number>();
  const spellings: Map<string, number>[] = [];
  const used: Used[][] = [];
  const rows: number[][] = [];
  for (const equation of equations) {
    const row: number[] = [];
    for (const { scout, used: part } of equation.parts) {
      const key = scout.toLowerCase();
      let index = indexByKey.get(key);
      if (index === undefined) {
        index = spellings.length;
        indexByKey.set(key, index);
        spellings.push(new Map());
        used.push([]);
      }
      const names = spellings[index] as Map<string, number>;
      names.set(scout, (names.get(scout) ?? 0) + 1);
      (used[index] as Used[]).push(part);
      row.push(index);
    }
    rows.push(row);
  }

  const misses = solveRidge(
    rows,
    equations.map((e) => e.official - e.scouted),
    spellings.length,
  );
  const scouts: ScoutScore[] = spellings.map((names, i) => {
    const miss = misses[i] as number;
    const list = (used[i] as Used[])
      .slice()
      .sort((a, b) => matchOrder(a.matchKey) - matchOrder(b.matchKey));
    return {
      name: commonest(names),
      miss,
      robots: list.length,
      enough: list.length >= minRobots,
      band: bandOf(miss),
      used: list,
    };
  });
  scouts.sort(
    (a, b) =>
      Number(b.enough) - Number(a.enough) ||
      Math.abs(b.miss) - Math.abs(a.miss) ||
      byCode(a.name, b.name),
  );

  const captures = equations
    .filter((e) => e.official > 0)
    .map((e) => e.scouted / e.official);
  return {
    scouts,
    equations: equations.length,
    skipped,
    incomplete,
    averageCapture:
      captures.length === 0
        ? null
        : captures.reduce((a, b) => a + b, 0) / captures.length,
  };
}
