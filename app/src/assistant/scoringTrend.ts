import { matchLabel } from "../data/matchKey";
import type { SeasonRow } from "../team/history";
import { type AssistantRequest, minimumChars } from "./queue";
import { oneDecimal as n, phaseSplit, worldRank } from "./teamBrief";

export const minimumMatches = 3;

export interface MatchScorePoint {
  key: string;
  total: number;
  auto: number;
  teleop: number;
  endgame: number;
  penalties: number;
  alliance: string;
}

export const trendKey = (
  eventKey: string,
  team: number,
  seasons: SeasonRow[],
) => {
  const years = seasons.map((s) => s.year).sort((a, b) => a - b);
  return `scoring-trend:${eventKey}:${team}${years.length === 0 ? "" : `:${years.join("-")}`}`;
};

export const trendSystem =
  "You explain the shape of an FRC team's scoring trend for a strategy lead. The numbers below are already computed; your job is the reasons, not the arithmetic. Point only at patterns visible in the tables given to you: a phase that moved differently from the rest, penalties clustering in certain matches, an alliance colour change, a run of matches trending the same direction, a season whose EPA rank sits well above or below the current one. Never invent a cause the tables do not show, and say plainly when the numbers do not explain themselves. The two tables are in different units: per-match totals are this event's scouting points and season rows are EPA, so never compare a number from one against a number from the other, and never treat a season's EPA points as comparable to another season's. Compare seasons only on the unitless scale, the normalized scale, or the world rank. A cycle-time table, if present, covers only the handful of matches someone filmed, never the whole event: never describe it as the team's general or typical cycle time, only as what those specific filmed matches showed.";

function seasonLine(season: SeasonRow): string {
  const split = phaseSplit(season);
  const parts = [
    season.unitless !== null && `unitless EPA ${n(season.unitless)}`,
    season.norm !== null &&
      `normalized EPA ${n(season.norm)} (1500 is average)`,
    worldRank(season) ?? false,
    `record ${season.wins}-${season.losses}-${season.ties}`,
    season.totalPoints !== null &&
      `EPA ${n(season.totalPoints)} points in that season's game, not comparable across seasons`,
    split !== "" && `phase split ${split}`,
  ].filter((p): p is string => p !== false);
  return `${season.year}: ${parts.join(", ")}`;
}

function trendPrompt(
  team: number,
  series: MatchScorePoint[],
  seasons: SeasonRow[],
): string {
  const lines = [
    `Below is team ${team}'s total score per match at one event, in the order the matches were played, already computed from scouting data. Each line also breaks the total into auton, teleop and endgame, the penalties called that match, and which alliance the team played on.`,
    "",
    "Write, in at most five lines, why the trend looks the way it does. Name the matches you are pointing at. If the numbers do not show a clear reason, say so instead of guessing.",
    "",
    seasons.length === 0
      ? "No season-by-season history is available for this team, so do not speculate about previous seasons."
      : "A season history table follows the matches. Use it only to say whether this event reads as normal, better or worse for this team than its recent seasons, and say which season you mean. Judge that on the unitless scale, the normalized scale or the world rank, never on EPA points, which mean different things in different games.",
    "",
    "Matches (total / auton / teleop / endgame / penalties / alliance), in this event's scouting points:",
    ...series.map(
      (p) =>
        `- ${matchLabel(p.key)}: ${n(p.total)} / ${n(p.auto)} / ${n(p.teleop)} / ${n(p.endgame)} / ${p.penalties} pen / ${p.alliance === "" ? "unknown alliance" : p.alliance}`,
    ),
  ];
  if (seasons.length > 0) {
    lines.push(
      "",
      "Season history (EPA, newest first):",
      ...seasons.map((s) => `- ${seasonLine(s)}`),
    );
  }
  lines.push("");
  return lines.join("\n");
}

export function trendRequest(
  eventKey: string,
  team: number,
  series: MatchScorePoint[],
  seasons: SeasonRow[],
): AssistantRequest | null {
  if (series.length < minimumMatches) return null;
  return {
    cacheKey: trendKey(eventKey, team, seasons),
    system: trendSystem,
    prompt: trendPrompt(team, series, seasons),
    minimumChars,
    coverage: series.length,
  };
}
