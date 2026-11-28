import { parseTeams } from "../data/tbaEvent";
import { teamKey } from "../data/tbaKey";
import { parseMatches, tbaGet } from "../scout/tba";
import { buildReplay, type Replay } from "./replay";

const eventKeyPattern = /^\d{4}[a-z][a-z0-9]*$/;

export function parseEventKey(text: string): string | null {
  const key = text.trim().toLowerCase();
  return eventKeyPattern.test(key) ? key : null;
}

export async function loadReplay(
  eventKey: string,
  apiKey: string | null = null,
  fetcher: typeof fetch = fetch,
): Promise<Replay> {
  const key = apiKey ?? (await teamKey());
  if (!key) throw new Error("No TBA key available. Sign in and go online.");
  const base = `/event/${encodeURIComponent(eventKey)}`;
  const [matches, teams] = await Promise.all([
    tbaGet(`${base}/matches/simple`, key, fetcher),
    tbaGet(`${base}/teams/simple`, key, fetcher).catch(() => []),
  ]);
  const replay = buildReplay(parseMatches(matches), parseTeams(teams));
  if (replay.matches.length === 0) {
    throw new Error(`${eventKey} has no played matches to replay.`);
  }
  return replay;
}
