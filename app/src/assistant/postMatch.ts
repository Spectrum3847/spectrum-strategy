import {
  type Sections,
  sectionKeys,
  sectionLabels,
} from "../reports/postMatch";
import {
  type AssistantRequest,
  minimumChars,
  untrustedSentence,
  wrapUntrusted,
} from "./queue";

export const postMatchKey = (eventKey: string, matchId: string) =>
  `post-match-analysis:${eventKey}_${matchId}`;

export const postMatchSystem = `You summarise one FRC match for a strategy lead, from the lead's own written account and the official match result. Be concrete and short. Use only what is given; never invent a detail, a score, or a cause that is not in the text below. ${untrustedSentence}`;

export interface MatchResult {
  red: number[];
  blue: number[];
  redScore: number | null;
  blueScore: number | null;
  winner: "red" | "blue" | null;
}

function accountBlock(report: Sections): string {
  return sectionKeys
    .flatMap((key) => {
      const text = report[key].trim();
      return text === "" ? [] : [`${sectionLabels[key]}:\n${text}\n`];
    })
    .join("\n")
    .trimEnd();
}

function resultLine(match: MatchResult | null, us: number | null) {
  if (match === null || match.redScore === null || match.blueScore === null) {
    return null;
  }
  const side =
    us === null
      ? null
      : match.red.includes(us)
        ? "red"
        : match.blue.includes(us)
          ? "blue"
          : null;
  if (side === null) return `Red ${match.redScore} - blue ${match.blueScore}.`;
  const ours = side === "red" ? match.redScore : match.blueScore;
  const theirs = side === "red" ? match.blueScore : match.redScore;
  const outcome =
    match.winner === null ? "Tied" : match.winner === side ? "Won" : "Lost";
  return `${outcome} ${ours} - ${theirs}.`;
}

export function postMatchRequest(
  eventKey: string,
  matchId: string,
  report: Sections,
  match: MatchResult | null,
  us: number | null,
): AssistantRequest | null {
  const account = accountBlock(report);
  if (account === "") return null;
  const result = resultLine(match, us);
  const prompt = [
    "Here is a strategy lead's account of one match, by phase, and the official result if it has posted.",
    "",
    wrapUntrusted(account),
    ...(result === null ? [] : ["", "Official result:", result]),
    "",
    "Write, in at most four lines: what happened, whether the lead's account lines up with the result, and anything worth carrying into the next match with this robot. Do not repeat the account back word for word. Do not add a preamble.",
    "",
  ].join("\n");
  return {
    cacheKey: postMatchKey(eventKey, matchId),
    system: postMatchSystem,
    prompt,
    minimumChars,
  };
}
