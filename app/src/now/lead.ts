import type { EventEntry } from "../data/parse";
import { type Brief, briefId, isEmptyBrief, matchIdOf } from "../match/brief";
import type { ScheduledMatch } from "../scout/schedule";
import { entryMatchKey } from "../team/stats";
import { compareMatches, isPlayed, matchLabel } from "./matches";
import { lastPlayedQual } from "./summary";

export interface LastResult {
  match: ScheduledMatch;
  label: string;
  alliance: "Red" | "Blue";
  ours: number;
  theirs: number;
  outcome: "won" | "lost" | "tied";
}

export function lastResult(
  schedule: ScheduledMatch[],
  team: number,
): LastResult | null {
  const played = schedule
    .filter(
      (m) => isPlayed(m) && (m.red.includes(team) || m.blue.includes(team)),
    )
    .sort(compareMatches)
    .at(-1);
  if (!played) return null;
  const red = played.red.includes(team);
  const ours = (red ? played.redScore : played.blueScore) ?? 0;
  const theirs = (red ? played.blueScore : played.redScore) ?? 0;
  return {
    match: played,
    label: matchLabel(played),
    alliance: red ? "Red" : "Blue",
    ours,
    theirs,
    outcome: ours > theirs ? "won" : ours < theirs ? "lost" : "tied",
  };
}

export type BriefStatus = "ready" | "draft" | "none";

export function briefStatus(
  briefs: Brief[],
  eventKey: string,
  matchKey: string,
): BriefStatus {
  const id = briefId(eventKey, matchIdOf(eventKey, matchKey));
  const brief = briefs.find((b) => b.id === id);
  if (!brief) return "none";
  if (brief.ready) return "ready";
  return isEmptyBrief(brief) ? "none" : "draft";
}

export const coverageWindow = 10;

export interface CoverageGap {
  match: ScheduledMatch;
  label: string;
  teams: number[];
}

export interface Coverage {
  from: number | null;
  through: number | null;
  gaps: CoverageGap[];
  robots: number;
}

type EntryRef = Pick<
  EventEntry,
  "id" | "teamNumber" | "tbaMatchKey" | "fieldValues"
>;

export function coverage(
  schedule: ScheduledMatch[],
  entries: EntryRef[],
): Coverage {
  const through = lastPlayedQual(schedule);
  if (through === null) return { from: null, through, gaps: [], robots: 0 };
  const seen = new Map<string, Set<number>>();
  for (const entry of entries) {
    const key = entryMatchKey(entry);
    seen.set(key, (seen.get(key) ?? new Set()).add(entry.teamNumber));
  }
  const from = Math.max(1, through - coverageWindow + 1);
  const gaps: CoverageGap[] = [];
  let robots = 0;
  const recent = schedule
    .filter(
      (m) =>
        m.compLevel === "qm" &&
        isPlayed(m) &&
        m.matchNumber >= from &&
        m.matchNumber <= through,
    )
    .sort(compareMatches);
  for (const match of recent) {
    const scouted = new Set([
      ...(seen.get(match.key.toLowerCase()) ?? []),
      ...(seen.get(`typed:${match.matchNumber}`) ?? []),
    ]);
    const teams = [...match.red, ...match.blue].filter((t) => !scouted.has(t));
    if (teams.length > 0) {
      gaps.push({ match, label: matchLabel(match), teams });
      robots += teams.length;
    }
  }
  return { from, through, gaps, robots };
}
