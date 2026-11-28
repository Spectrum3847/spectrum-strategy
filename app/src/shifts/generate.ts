import type {
  ShiftBlock,
  ShiftRosterEntry,
  ShiftRotation,
} from "../scout/credit";

export const stations = ["R1", "R2", "R3", "B1", "B2", "B3"] as const;
export const shiftLength = 6;
export const maxMatchCount = 999;

export type RedMatches = Map<number, Set<number>>;

const stationAt = (position: number, blocksHad: number) =>
  stations[(position + blocksHad) % stations.length] ?? "R1";

export function redInRange(
  red: Set<number> | undefined,
  start: number,
  end: number,
) {
  if (!red || red.size === 0) return false;
  for (let match = start; match <= end; match++)
    if (red.has(match)) return true;
  return false;
}

export function leastDoneStations(
  cols: number[],
  counts: number[][],
): string[] {
  const taken = new Set<number>();
  return cols.map((col) => {
    const done = counts[col] ?? [];
    let best = -1;
    for (let s = 0; s < stations.length; s++) {
      if (taken.has(s)) continue;
      if (best === -1 || (done[s] ?? 0) < (done[best] ?? 0)) best = s;
    }
    taken.add(best);
    done[best] = (done[best] ?? 0) + 1;
    return stations[best] ?? "R1";
  });
}

export function mergeAdjacent(blocks: ShiftBlock[]): ShiftBlock[] {
  const merged: ShiftBlock[] = [];
  for (const block of blocks) {
    const last = merged[merged.length - 1];
    if (
      last &&
      block.startMatch === last.endMatch + 1 &&
      block.station === last.station
    ) {
      merged[merged.length - 1] = { ...last, endMatch: block.endMatch };
    } else {
      merged.push(block);
    }
  }
  return merged;
}

function toRotations(
  roster: ShiftRosterEntry[],
  blocks: ShiftBlock[][],
): ShiftRotation[] {
  return roster.map((entry, i) => ({
    uid: entry.uid,
    blocks: mergeAdjacent(blocks[i] ?? []),
  }));
}

function fixedGroups(
  matchCount: number,
  roster: ShiftRosterEntry[],
): ShiftRotation[] {
  const groups: number[][] = [];
  for (let i = 0; i < roster.length; i += shiftLength) {
    groups.push(
      Array.from(
        { length: Math.min(shiftLength, roster.length - i) },
        (_, j) => i + j,
      ),
    );
  }
  const blocks: ShiftBlock[][] = roster.map(() => []);
  const fullRounds = Math.floor(matchCount / shiftLength);
  const remainder = matchCount % shiftLength;

  for (let round = 0; round < fullRounds; round++) {
    const start = round * shiftLength + 1;
    const end = start + shiftLength - 1;
    const group = groups[round % groups.length] ?? [];
    const blocksHad =
      groups.length === 1 ? 0 : Math.floor(round / groups.length);
    group.forEach((idx, pos) => {
      blocks[idx]?.push({
        startMatch: start,
        endMatch: end,
        station: stationAt(pos, blocksHad),
      });
    });
  }

  if (remainder > 0) {
    const tailRound = fullRounds > 0 ? fullRounds - 1 : 0;
    const tail = groups[tailRound % groups.length] ?? [];
    tail.forEach((idx, pos) => {
      const own = blocks[idx];
      if (!own) return;
      const last = fullRounds > 0 ? own.pop() : undefined;
      own.push(
        last
          ? { ...last, endMatch: matchCount }
          : { startMatch: 1, endMatch: matchCount, station: stationAt(pos, 0) },
      );
    });
  }
  return toRotations(roster, blocks);
}

function aroundRed(
  matchCount: number,
  roster: ShiftRosterEntry[],
  red: RedMatches,
): ShiftRotation[] {
  const blocks: ShiftBlock[][] = roster.map(() => []);
  const lastEnd = roster.map(() => -matchCount);
  const counts = roster.map(() => stations.map(() => 0));
  const fullRounds = Math.floor(matchCount / shiftLength);
  const remainder = matchCount % shiftLength;
  let lastRound: number[] = [];

  for (let round = 0; round < fullRounds; round++) {
    const start = round * shiftLength + 1;
    const end = start + shiftLength - 1;
    const chosen = roster
      .map((_, col) => col)
      .filter((col) => !redInRange(red.get(col), start, end))
      .sort((a, b) => {
        const breakA = start - 1 - (lastEnd[a] ?? 0);
        const breakB = start - 1 - (lastEnd[b] ?? 0);
        return breakA !== breakB ? breakB - breakA : a - b;
      })
      .slice(0, shiftLength);
    const picked = leastDoneStations(chosen, counts);
    chosen.forEach((col, i) => {
      blocks[col]?.push({
        startMatch: start,
        endMatch: end,
        station: picked[i] ?? null,
      });
      lastEnd[col] = end;
    });
    lastRound = chosen;
  }

  if (remainder > 0) {
    if (fullRounds > 0) {
      for (const col of lastRound) {
        const last = blocks[col]?.pop();
        if (last) blocks[col]?.push({ ...last, endMatch: matchCount });
      }
    } else {
      const chosen = roster
        .map((_, col) => col)
        .filter((col) => !redInRange(red.get(col), 1, matchCount))
        .slice(0, shiftLength);
      const picked = leastDoneStations(chosen, counts);
      chosen.forEach((col, i) => {
        blocks[col]?.push({
          startMatch: 1,
          endMatch: matchCount,
          station: picked[i] ?? null,
        });
      });
    }
  }
  return toRotations(roster, blocks);
}

export function buildRotations(
  matchCount: number,
  roster: ShiftRosterEntry[],
  red: RedMatches = new Map(),
): ShiftRotation[] {
  if (matchCount > maxMatchCount) {
    throw new RangeError(`matchCount must not exceed ${maxMatchCount}`);
  }
  if (roster.length === 0 || matchCount <= 0) return [];
  const anyRed = [...red.values()].some((set) => set.size > 0);
  return anyRed
    ? aroundRed(matchCount, roster, red)
    : fixedGroups(matchCount, roster);
}
