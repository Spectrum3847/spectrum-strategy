const base = "https://www.thebluealliance.com/api/v3";

export interface TeamRank {
  rank: number;
  of: number;
  wins: number;
  losses: number;
  ties: number;
  played: number;
}

const count = (v: unknown) => (typeof v === "number" && v >= 0 ? v : 0);

export function parseRank(raw: unknown, team: number): TeamRank | null {
  const rankings = (raw as { rankings?: unknown } | null)?.rankings;
  if (!Array.isArray(rankings)) return null;
  const mine = rankings.find(
    (r) => (r as { team_key?: unknown } | null)?.team_key === `frc${team}`,
  ) as
    | {
        rank?: unknown;
        matches_played?: unknown;
        record?: { wins?: unknown; losses?: unknown; ties?: unknown };
      }
    | undefined;
  if (!mine || typeof mine.rank !== "number") return null;
  return {
    rank: mine.rank,
    of: rankings.length,
    wins: count(mine.record?.wins),
    losses: count(mine.record?.losses),
    ties: count(mine.record?.ties),
    played: count(mine.matches_played),
  };
}

export async function fetchRankings(
  eventKey: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<unknown> {
  const response = await fetcher(
    `${base}/event/${encodeURIComponent(eventKey)}/rankings`,
    { headers: { "X-TBA-Auth-Key": apiKey } },
  );
  if (!response.ok) throw new Error(`TBA answered ${response.status}`);
  return response.json();
}

export function recordText(rank: TeamRank): string {
  return `${rank.wins}-${rank.losses}-${rank.ties}`;
}
