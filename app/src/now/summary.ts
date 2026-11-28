import type { ScoutShifts, ShiftBlock } from "../scout/credit";
import type { ScheduledMatch } from "../scout/schedule";
import { compareMatches, isPlayed, matchLabel } from "./matches";

export interface OurMatch {
  match: ScheduledMatch;
  label: string;
  alliance: "Red" | "Blue";
  ourSide: number[];
  opponents: number[];
  away: number;
}

export type NowSummary =
  | { state: "no-schedule" }
  | { state: "not-on-schedule" }
  | {
      state: "ready";
      next: OurMatch | null;
      later: OurMatch[];
      playedCount: number;
      totalCount: number;
      scheduleDone: boolean;
    };

export function lastPlayedQual(schedule: ScheduledMatch[]): number | null {
  let last: number | null = null;
  for (const m of schedule) {
    if (m.compLevel === "qm" && isPlayed(m)) {
      last = Math.max(last ?? 0, m.matchNumber);
    }
  }
  return last;
}

export function buildNow(schedule: ScheduledMatch[], team: number): NowSummary {
  if (schedule.length === 0) return { state: "no-schedule" };
  const ordered = [...schedule].sort(compareMatches);
  const ours: OurMatch[] = [];
  let playedCount = 0;
  let totalCount = 0;
  let unplayed = 0;
  for (const match of ordered) {
    const played = isPlayed(match);
    const isRed = match.red.includes(team);
    if (isRed || match.blue.includes(team)) {
      totalCount += 1;
      if (played) playedCount += 1;
      else {
        ours.push({
          match,
          label: matchLabel(match),
          alliance: isRed ? "Red" : "Blue",
          ourSide: isRed ? match.red : match.blue,
          opponents: isRed ? match.blue : match.red,
          away: unplayed,
        });
      }
    }
    if (!played) unplayed += 1;
  }
  if (totalCount === 0) return { state: "not-on-schedule" };
  return {
    state: "ready",
    next: ours[0] ?? null,
    later: ours.slice(1),
    playedCount,
    totalCount,
    scheduleDone: unplayed === 0 && ordered.some((m) => m.compLevel === "f"),
  };
}

export type ShiftSummary =
  | { status: "no-grid" }
  | { status: "not-scheduled" }
  | { status: "done" }
  | { status: "next"; block: ShiftBlock; away: number };

export function nextShift(
  shifts: ScoutShifts | null,
  uids: string[],
  lastQual: number | null,
): ShiftSummary {
  if (shifts === null) return { status: "no-grid" };
  const rotation = shifts.rotations.find(
    (r) => r.uid !== "" && uids.includes(r.uid),
  );
  if (!rotation) return { status: "not-scheduled" };
  const floor = lastQual ?? 0;
  const block = [...rotation.blocks]
    .sort((a, b) => a.startMatch - b.startMatch)
    .find((b) => b.endMatch >= floor + 1);
  if (!block) return { status: "done" };
  return {
    status: "next",
    block,
    away: Math.max(0, block.startMatch - floor - 1),
  };
}
