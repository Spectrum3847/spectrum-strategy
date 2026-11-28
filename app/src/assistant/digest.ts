import {
  type AssistantRequest,
  minimumChars,
  untrustedSentence,
  wrapUntrusted,
} from "./queue";

export const minimumNotes = 4;

export interface DigestNote {
  match: string;
  author: string;
  text: string;
}

export const digestSystem = `You summarise FRC scouting comments for a strategy lead who has to brief a drive team before a match. Be concrete and short. Use the numbers and behaviours the scouters actually wrote down. Never invent a detail that is not in the comments, and say so plainly when the comments do not cover something. ${untrustedSentence}`;

export const digestKey = (eventKey: string, team: number) =>
  `comment-digest:${eventKey}:${team}`;

const oneLine = (text: string) => text.replace(/\s+/g, " ").trim();

const context = (note: DigestNote) => {
  const parts = [
    note.match !== "" && `match ${note.match}`,
    note.author !== "" && `by ${note.author}`,
  ].filter((p): p is string => p !== false);
  return parts.length === 0 ? "unattributed" : parts.join(", ");
};

function digestPrompt(team: number, notes: DigestNote[]): string {
  const block = notes
    .map((n) => `- ${context(n)}: ${oneLine(n.text)}`)
    .join("\n")
    .trimEnd();
  return [
    `Below are ${notes.length} comments written by scouters about team ${team} at one event. Each line is one comment, with the match it came from, the part of the match it is about, and who wrote it.`,
    "",
    "Write, in at most six lines:",
    "- What the scouters keep saying about this robot. Only themes that more than one comment supports.",
    "- Where the scouters disagree with each other. Two scouters contradicting each other about the same robot is the most useful thing here, so name the disagreement rather than averaging it away.",
    "- Anything a drive team would want warning about: breakdowns, penalties, defence, a driver having a bad day.",
    "",
    "Do not repeat the comments back. Do not add a preamble.",
    "",
    "Comments:",
    wrapUntrusted(block),
    "",
  ].join("\n");
}

export function digestRequest(
  eventKey: string,
  team: number,
  notes: DigestNote[],
): AssistantRequest | null {
  if (notes.length < minimumNotes) return null;
  return {
    cacheKey: digestKey(eventKey, team),
    system: digestSystem,
    prompt: digestPrompt(team, notes),
    minimumChars,
    coverage: notes.length,
  };
}
