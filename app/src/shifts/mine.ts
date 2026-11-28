import { lastPlayedQual } from "../now/summary";
import type { ScoutShifts, ShiftBlock, ShiftTradeDoc } from "../scout/credit";
import {
  qualMatches,
  type RemoteEntry,
  type ScheduledMatch,
  stationOf,
} from "../scout/schedule";
import { sameSpan, tradedWith } from "./trades";

export function playedThrough(
  schedule: ScheduledMatch[],
  entries: RemoteEntry[],
): number | null {
  const hasScores = qualMatches(schedule).some(
    (m) => m.redScore !== undefined || m.blueScore !== undefined,
  );
  if (hasScores) return lastPlayedQual(schedule);
  const seen = new Map<string, Set<string>>();
  for (const e of entries) {
    if (!e.tbaMatchKey) continue;
    const key = e.tbaMatchKey.toLowerCase();
    const robots = seen.get(key) ?? new Set<string>();
    robots.add(stationOf(e.fieldValues) || e.id);
    seen.set(key, robots);
  }
  let played: number | null = null;
  for (const m of qualMatches(schedule)) {
    if ((seen.get(m.key.toLowerCase())?.size ?? 0) >= 2) {
      played = Math.max(played ?? 0, m.matchNumber);
    }
  }
  return played;
}

export interface MyBlock {
  block: ShiftBlock;
  tradedWith: string | null;
  away: "done" | number | null;
}

export function myBlocks(
  shifts: ScoutShifts,
  trades: ShiftTradeDoc[],
  uid: string,
  played: number | null,
): MyBlock[] | null {
  if (uid === "") return null;
  const rotation = shifts.rotations.find((r) => r.uid === uid);
  if (!rotation) return null;
  const traded = tradedWith(trades, uid);
  return [...rotation.blocks]
    .sort((a, b) => a.startMatch - b.startMatch)
    .map((block) => {
      let away: MyBlock["away"] = null;
      if (played !== null) {
        away =
          block.endMatch <= played
            ? "done"
            : Math.max(0, block.startMatch - played - 1);
      }
      return {
        block,
        tradedWith: traded.find((t) => sameSpan(t.block, block))?.name ?? null,
        away,
      };
    });
}

export function rangeText(b: { startMatch: number; endMatch: number }) {
  return b.startMatch === b.endMatch
    ? `Q${b.startMatch}`
    : `Q${b.startMatch} to Q${b.endMatch}`;
}

export function awayText(away: MyBlock["away"]): string {
  if (away === null) return "";
  if (away === "done") return "Done";
  if (away === 0) return "On duty now";
  return away === 1 ? "1 match away" : `${away} matches away`;
}
