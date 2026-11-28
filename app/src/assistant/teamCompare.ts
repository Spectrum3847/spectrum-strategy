import {
  type AssistantRequest,
  minimumChars,
  untrustedSentence,
  wrapUntrusted,
} from "./queue";

export const compareKey = (eventKey: string, team: number) =>
  `team-compare:${eventKey}:${team}`;

export const comparePrompt =
  "Synthesize the provided quantitative data and scouter comments into a concise 2 bullet summary highlighting 1) Core strengths and scoring capability and vulnerabilities/fouls/disconnects and 2) any alliance tactical advice. Keep it under 50-75 words and don't use fluff.";

export const compareSystem = `You write a short tactical summary for an FRC strategy lead from a JSON payload of one team's stats and scouter comments. ${untrustedSentence}`;

export interface CompareFacts {
  teleopIqm: number | null;
  autoIqm: number | null;
  climbSuccessRate: number | null;
  cards: number;
  disconnects: number;
  comments: string[];
}

export function compareRequest(
  eventKey: string,
  team: number,
  scoutedEntries: number,
  facts: CompareFacts,
): AssistantRequest | null {
  if (scoutedEntries === 0) return null;
  const payload = {
    teamNumber: team,
    ...(facts.teleopIqm !== null && { teleopIqm: facts.teleopIqm }),
    ...(facts.autoIqm !== null && { autoIqm: facts.autoIqm }),
    ...(facts.climbSuccessRate !== null && {
      climbSuccessRate: facts.climbSuccessRate,
    }),
    redOrYellowCards: facts.cards,
    disconnects: facts.disconnects,
    scouterComments: facts.comments,
  };
  return {
    cacheKey: compareKey(eventKey, team),
    system: compareSystem,
    prompt: `${comparePrompt}\n\n${wrapUntrusted(JSON.stringify(payload))}`,
    minimumChars,
    coverage: facts.comments.length,
  };
}
