import type { ScheduledMatch } from "./schedule";

const base = "https://www.thebluealliance.com/api/v3";

interface TbaAlliance {
  team_keys?: unknown;
  score?: unknown;
}
interface TbaMatch {
  key?: unknown;
  comp_level?: unknown;
  match_number?: unknown;
  time?: unknown;
  predicted_time?: unknown;
  alliances?: { red?: TbaAlliance; blue?: TbaAlliance };
}

const seconds = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? v : null;

const teams = (alliance: TbaAlliance | undefined): number[] =>
  Array.isArray(alliance?.team_keys)
    ? alliance.team_keys
        .map((k) => Number(String(k).replace(/^frc/, "")))
        .filter((n) => Number.isInteger(n) && n > 0)
    : [];

export function parseMatches(raw: unknown): ScheduledMatch[] {
  if (!Array.isArray(raw)) return [];
  const out: ScheduledMatch[] = [];
  for (const item of raw as TbaMatch[]) {
    if (
      typeof item?.key !== "string" ||
      typeof item.comp_level !== "string" ||
      typeof item.match_number !== "number"
    ) {
      continue;
    }
    out.push({
      key: item.key,
      compLevel: item.comp_level,
      matchNumber: item.match_number,
      red: teams(item.alliances?.red),
      blue: teams(item.alliances?.blue),
      time: seconds(item.time),
      predictedTime: seconds(item.predicted_time),
      redScore: seconds(item.alliances?.red?.score) ?? -1,
      blueScore: seconds(item.alliances?.blue?.score) ?? -1,
    });
  }
  return out.sort(
    (a, b) =>
      a.compLevel.localeCompare(b.compLevel) || a.matchNumber - b.matchNumber,
  );
}

export async function tbaGet(
  path: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<unknown> {
  const response = await fetcher(`${base}${path}`, {
    headers: { "X-TBA-Auth-Key": apiKey },
  });
  if (!response.ok) throw new Error(`TBA answered ${response.status}`);
  return response.json();
}

export async function fetchEventMatches(
  eventKey: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<ScheduledMatch[]> {
  return parseMatches(
    await tbaGet(
      `/event/${encodeURIComponent(eventKey)}/matches/simple`,
      apiKey,
      fetcher,
    ),
  );
}
