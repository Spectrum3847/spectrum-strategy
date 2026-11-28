import type {
  AwardRow,
  EventRow,
  Placement,
  SeasonRow,
  TeamHistory,
} from "../team/history";
import type { AssistantRequest } from "./queue";

export const minimumEvents = 2;
export const fullBriefEvents = 4;

export const wordLimit = (events: number) =>
  events >= fullBriefEvents ? 200 : 90;

export const briefKey = (team: number, events: EventRow[]) =>
  `team-brief:${team}:${events
    .map((e) => e.event)
    .sort()
    .join(",")}`;

export const briefSystem =
  "You write a short brief on one FRC team's history for a drive coach to read before an alliance meeting. You are given finished numbers; your job is to say what they mean, never to recompute them. Every sentence must name the event or season it comes from. If you cannot point at a specific row you were given, do not write the claim at all: drop it rather than softening it, because a coach may repeat it out loud to another team. Do not infer anything about a robot's mechanisms, its drivers, its scouting reputation or its intentions from a rank or a win-loss record, and do not describe a team as unreliable, inconsistent or weak unless a number you were given shows it and you cite that number. Compare seasons only on the unitless or normalized EPA scale, or on world rank, never on EPA points, which mean different things in different games. A lower rank number is better than a higher one, for world rank and for qualification rank alike, so rank 222 is a better season than rank 307 and moving to a lower number is an improvement, never a concern. Use each alliance role exactly as it is given to you: a first pick is not a captain, and a captain is not a pick. Do not upgrade or downgrade a role to make a sentence read better. Say plainly when the history is too thin to support a section, and leave that section out.";

export const oneDecimal = (value: number) => value.toFixed(1);
const n = oneDecimal;

export const record = (w: number, l: number, t: number) =>
  `${w}-${l}${t > 0 ? `-${t}` : ""}`;

export function phaseSplit(row: {
  autoPoints: number | null;
  teleopPoints: number | null;
  endgamePoints: number | null;
}): string {
  const phases = [
    row.autoPoints !== null && `auton ${n(row.autoPoints)}`,
    row.teleopPoints !== null && `teleop ${n(row.teleopPoints)}`,
    row.endgamePoints !== null && `endgame ${n(row.endgamePoints)}`,
  ].filter((p): p is string => p !== false);
  return phases.join(" / ");
}

export function worldRank(season: SeasonRow): string | null {
  if (season.epaRank === null) return null;
  return season.epaRankTeamCount === null
    ? `world rank ${season.epaRank}`
    : `world rank ${season.epaRank} of ${season.epaRankTeamCount}`;
}

function seasonLine(season: SeasonRow): string {
  const parts = [
    season.unitless !== null && `unitless EPA ${n(season.unitless)}`,
    season.norm !== null &&
      `normalized EPA ${n(season.norm)} (1500 is average)`,
    worldRank(season) ?? false,
    `record ${season.wins}-${season.losses}-${season.ties}`,
  ].filter((p): p is string => p !== false);
  return `${season.year}: ${parts.join(", ")}`;
}

function eventLine(event: EventRow): string {
  const split = phaseSplit(event);
  const parts = [
    event.rank === null
      ? "no qualification rank recorded"
      : event.numTeams === null
        ? `qualification rank ${event.rank}`
        : `qualification rank ${event.rank} of ${event.numTeams}`,
    `record ${record(event.wins, event.losses, event.ties)}`,
    event.totalPoints !== null &&
      `EPA ${n(event.totalPoints)} in that season's points`,
    split !== "" && `phase split ${split}`,
  ].filter((p): p is string => p !== false);
  const label = event.eventName === "" ? event.event : event.eventName;
  return `${event.year} ${event.event} (${label}): ${parts.join(", ")}`;
}

const roundNames: Record<string, string> = {
  f: "the final",
  sf: "the semifinal",
  qf: "the quarterfinal",
  ef: "the eighthfinal",
};

const roles = ["alliance captain", "first pick", "second pick"];

function placementLine(p: Placement): string {
  const round =
    p.roundReached === ""
      ? "no playoff round recorded"
      : `reached ${roundNames[p.roundReached] ?? p.roundReached}`;
  return `- ${p.eventKey}: alliance ${p.allianceNumber}, ${roles[p.pickIndex] ?? "backup"}, ${round}`;
}

const awardLine = (a: AwardRow) =>
  `- ${a.year} ${a.eventKey}: ${a.name}${a.isWinOrFinalist ? " (playoff result)" : " (judged award)"}`;

function briefPrompt(team: number, history: TeamHistory): string {
  const { seasons, events, alliances, awards } = history;
  const lines = [
    `Write a brief on FRC team ${team} from the history below. Use exactly these three headings, and drop any heading you cannot support from the rows given:`,
    "",
    "How they perform: two or three lines on what their results say about them, citing events.",
    "How they got there: how their qualification rank and record at each event turned into the position they finished in. An award named Winner or Finalist is a playoff result; a judged award is not.",
    `Watch out for: at most three specific things a coach should know, each one citing the event or season that shows it. Only these count as a thing to flag, and only when the rows show it: a losing win-loss record at an event, a qualification rank far worse than this team's own other events, one phase of the split much weaker than the others, or a season whose world rank is well below the other. If none of those apply, write exactly "Nothing in these results stands out to flag." and nothing else under this heading. Do not comment on your own reasoning or on whether the data supports you. Do not turn a low rank or a losing record into a claim about drivers, reliability or robot design: report the number and let the coach judge it.`,
    "",
    `Keep the whole thing under ${wordLimit(events.length)} words. Numbers below are already computed. A rank is where the team finished qualification at that event, not where it placed overall, so do not call rank 2 a second-place finish.`,
  ];
  if (events.length < fullBriefEvents) {
    lines.push(
      "",
      `This team has only ${events.length} events on record, which is thin. Say so in the first line, keep every section to one sentence, and do not describe a pattern: with this few events there are results, not tendencies.`,
    );
  }
  if (seasons.length > 0) {
    lines.push(
      "",
      "Seasons (EPA, newest first):",
      ...seasons.map((s) => `- ${seasonLine(s)}`),
    );
  }
  if (events.length > 0) {
    lines.push(
      "",
      "Events (newest first):",
      ...events.map((e) => `- ${eventLine(e)}`),
    );
  }
  if (alliances.length > 0) {
    lines.push(
      "",
      "Alliance selection (how the field read them):",
      ...alliances.map(placementLine),
    );
  }
  if (awards.length === 0) {
    lines.push(
      "",
      "Awards: none in these seasons. That is not itself a weakness, so do not present it as one.",
    );
  } else {
    lines.push("", "Awards:", ...awards.map(awardLine));
  }
  lines.push("");
  return lines.join("\n");
}

export function briefRequest(
  team: number,
  history: TeamHistory,
): AssistantRequest | null {
  const events = history.events.length;
  if (events < minimumEvents) return null;
  return {
    cacheKey: briefKey(team, history.events),
    system: briefSystem,
    prompt: briefPrompt(team, history),
    minimumChars: events >= fullBriefEvents ? 200 : 100,
    coverage: events,
  };
}
