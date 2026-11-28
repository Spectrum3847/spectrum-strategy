import type {
  ScoutShifts,
  ShiftBlock,
  ShiftRosterEntry,
  Span,
} from "../scout/credit";
import {
  leastDoneStations,
  maxMatchCount,
  mergeAdjacent,
  type RedMatches,
  redInRange,
  shiftLength,
  stations,
} from "./generate";
import { rangeText } from "./mine";
import { addScouts, redMatches } from "./schedule";

const weight = (b: Span) =>
  Math.max(1, Math.floor((b.endMatch - b.startMatch + 1) / shiftLength));

export const nextBlockStart = (done: number | null) =>
  Math.ceil(Math.max(0, done ?? 0) / shiftLength) * shiftLength + 1;

export function rebuildStart(shifts: ScoutShifts, fromMatch: number): number {
  let end = Math.max(0, fromMatch - 1);
  for (const rotation of shifts.rotations) {
    for (const b of rotation.blocks) {
      if (b.startMatch < fromMatch) end = Math.max(end, b.endMatch);
    }
  }
  return nextBlockStart(end);
}

export function rebuildRounds(start: number, matchCount: number): Span[] {
  const rounds: Span[] = [];
  for (let s = start; s <= matchCount; s += shiftLength) {
    rounds.push({
      startMatch: s,
      endMatch: Math.min(s + shiftLength - 1, matchCount),
    });
  }
  const last = rounds[rounds.length - 1];
  const before = rounds[rounds.length - 2];
  if (last && before && last.endMatch - last.startMatch + 1 < shiftLength) {
    before.endMatch = last.endMatch;
    rounds.pop();
  }
  return rounds;
}

export function rebuildFrom(
  shifts: ScoutShifts,
  fromMatch: number,
  unavailable: RedMatches = redMatches(shifts),
): ScoutShifts {
  const { roster, matchCount } = shifts;
  const cols = roster.map((_, col) => col);
  const kept = cols.map((col) =>
    (shifts.rotations[col]?.blocks ?? []).filter(
      (b) => b.startMatch < fromMatch,
    ),
  );
  const added: ShiftBlock[][] = cols.map(() => []);
  const done = kept.map((blocks) =>
    blocks.reduce((sum, b) => sum + weight(b), 0),
  );
  const lastEnd = kept.map((blocks) =>
    blocks.reduce((end, b) => Math.max(end, b.endMatch), -maxMatchCount),
  );
  const stationCounts = kept.map((blocks) => {
    const counts = stations.map(() => 0);
    for (const b of blocks) {
      const at = (stations as readonly (string | null)[]).indexOf(b.station);
      if (at >= 0) counts[at] = (counts[at] ?? 0) + weight(b);
    }
    return counts;
  });

  const rounds = rebuildRounds(rebuildStart(shifts, fromMatch), matchCount);
  for (const round of rounds) {
    const free = cols
      .filter(
        (c) =>
          !redInRange(unavailable.get(c), round.startMatch, round.endMatch),
      )
      .sort(
        (a, b) =>
          (done[a] ?? 0) - (done[b] ?? 0) ||
          (lastEnd[a] ?? 0) - (lastEnd[b] ?? 0) ||
          a - b,
      );
    const rested = free.filter((c) => (lastEnd[c] ?? 0) < round.startMatch - 1);
    const chosen = [
      ...rested,
      ...free.filter((c) => !rested.includes(c)),
    ].slice(0, shiftLength);
    const picked = leastDoneStations(chosen, stationCounts);
    chosen.forEach((col, i) => {
      added[col]?.push({ ...round, station: picked[i] ?? null });
      done[col] = (done[col] ?? 0) + weight(round);
      lastEnd[col] = round.endMatch;
    });
  }

  return {
    ...shifts,
    rotations: roster.map((r, col) => ({
      uid: r.uid,
      blocks: [...(kept[col] ?? []), ...mergeAdjacent(added[col] ?? [])],
    })),
  };
}

export function rebuildProblems(
  shifts: ScoutShifts,
  from: number,
  unavailable: RedMatches = redMatches(shifts),
): string[] {
  const problems: string[] = [];
  const nameOf = (col: number) =>
    shifts.roster[col]?.name || `Scout ${col + 1}`;
  for (const round of rebuildRounds(from, shifts.matchCount)) {
    const where = rangeText(round);
    const on = shifts.rotations
      .map((r, col) => ({ col, blocks: r.blocks }))
      .filter(({ blocks }) =>
        blocks.some(
          (b) =>
            b.startMatch <= round.endMatch && b.endMatch >= round.startMatch,
        ),
      );
    if (on.length < shiftLength) {
      const empty = shiftLength - on.length;
      problems.push(
        `${where}: ${empty} of ${shiftLength} stations have no scout.`,
      );
    }
    const used = on.flatMap(({ blocks }) =>
      blocks
        .filter(
          (b) =>
            b.startMatch <= round.endMatch && b.endMatch >= round.startMatch,
        )
        .map((b) => b.station)
        .filter(Boolean),
    );
    if (new Set(used).size < used.length) {
      problems.push(`${where}: two scouts share a station.`);
    }
    for (const { col, blocks } of on) {
      if (redInRange(unavailable.get(col), round.startMatch, round.endMatch)) {
        problems.push(`${where}: ${nameOf(col)} is marked unavailable.`);
      }
      if (blocks.some((b) => b.endMatch === round.startMatch - 1)) {
        problems.push(`${where}: ${nameOf(col)} has no break.`);
      }
    }
  }
  return problems;
}

export interface RebuildSummary {
  from: number;
  keptShifts: number;
  newShifts: number;
  changed: string[];
  warnings: string[];
}

const after = (blocks: ShiftBlock[], from: number) =>
  JSON.stringify(blocks.filter((b) => b.startMatch >= from));

export function summarizeRebuild(
  before: ScoutShifts,
  next: ScoutShifts,
  from: number,
): RebuildSummary {
  let keptShifts = 0;
  let newShifts = 0;
  const changed: string[] = [];
  next.rotations.forEach((r, col) => {
    keptShifts += r.blocks.filter((b) => b.startMatch < from).length;
    newShifts += r.blocks.filter((b) => b.startMatch >= from).length;
    const was = before.rotations[col]?.blocks ?? [];
    if (after(was, from) !== after(r.blocks, from)) {
      changed.push(next.roster[col]?.name || `Scout ${col + 1}`);
    }
  });
  return {
    from,
    keptShifts,
    newShifts,
    changed,
    warnings: rebuildProblems(next, from),
  };
}

export function rebuildWithScouts(
  shifts: ScoutShifts,
  fromMatch: number,
  newScouts: ShiftRosterEntry[],
): { next: ScoutShifts; summary: RebuildSummary } | null {
  const joined = addScouts(shifts, newScouts);
  if (!joined) return null;
  const from = rebuildStart(joined, fromMatch);
  const next = rebuildFrom(joined, fromMatch);
  return { next, summary: summarizeRebuild(joined, next, from) };
}
