import { tbaGet } from "../scout/tba";
import { type CompLevel, matchOrder, parseMatchKey } from "./matchKey";

export interface EventTeam {
  number: number;
  nickname: string;
}

export interface TeamRanking {
  team: number;
  rank: number;
  wins: number;
  losses: number;
  ties: number;
}

export interface EventMatch {
  key: string;
  level: CompLevel;
  red: number[];
  blue: number[];
  redScore: number | null;
  blueScore: number | null;
  winner: "red" | "blue" | null;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const teamNumber = (key: unknown) => {
  const n = Number(String(key).replace(/^frc/, ""));
  return Number.isInteger(n) && n > 0 ? n : null;
};

export function parseTeams(raw: unknown): EventTeam[] {
  if (!Array.isArray(raw)) return [];
  const out: EventTeam[] = [];
  for (const t of raw) {
    if (!isRecord(t)) continue;
    const number = teamNumber(t.team_number);
    if (number === null) continue;
    out.push({
      number,
      nickname: typeof t.nickname === "string" ? t.nickname.trim() : "",
    });
  }
  return out.sort((a, b) => a.number - b.number);
}

export function parseRankings(raw: unknown): TeamRanking[] {
  const list = isRecord(raw) ? raw.rankings : null;
  if (!Array.isArray(list)) return [];
  const out: TeamRanking[] = [];
  for (const r of list) {
    if (!isRecord(r)) continue;
    const team = teamNumber(r.team_key);
    if (team === null || typeof r.rank !== "number") continue;
    const record = isRecord(r.record) ? r.record : {};
    const count = (v: unknown) => (typeof v === "number" ? v : 0);
    out.push({
      team,
      rank: r.rank,
      wins: count(record.wins),
      losses: count(record.losses),
      ties: count(record.ties),
    });
  }
  return out.sort((a, b) => a.rank - b.rank);
}

function side(alliance: unknown): { teams: number[]; score: number | null } {
  if (!isRecord(alliance)) return { teams: [], score: null };
  const keys = Array.isArray(alliance.team_keys) ? alliance.team_keys : [];
  return {
    teams: keys.map(teamNumber).filter((n): n is number => n !== null),
    score:
      typeof alliance.score === "number" && alliance.score >= 0
        ? alliance.score
        : null,
  };
}

export function parseEventMatches(raw: unknown): EventMatch[] {
  if (!Array.isArray(raw)) return [];
  const out: EventMatch[] = [];
  for (const m of raw) {
    if (!isRecord(m) || typeof m.key !== "string") continue;
    const ref = parseMatchKey(m.key);
    if (!ref) continue;
    const alliances = isRecord(m.alliances) ? m.alliances : {};
    const red = side(alliances.red);
    const blue = side(alliances.blue);
    const played = red.score !== null && blue.score !== null;
    const winning = m.winning_alliance;
    out.push({
      key: m.key,
      level: ref.level,
      red: red.teams,
      blue: blue.teams,
      redScore: red.score,
      blueScore: blue.score,
      winner:
        played && (winning === "red" || winning === "blue") ? winning : null,
    });
  }
  return out.sort((a, b) => matchOrder(a.key) - matchOrder(b.key));
}

export interface TbaEventSnapshot {
  fetchedAt: string;
  teams: EventTeam[];
  rankings: TeamRanking[];
  matches: EventMatch[];
}

export async function fetchEventSnapshot(
  eventKey: string,
  apiKey: string,
  previous: TbaEventSnapshot | null,
  fetcher: typeof fetch = fetch,
): Promise<TbaEventSnapshot> {
  const base = `/event/${encodeURIComponent(eventKey)}`;
  const [teams, rankings, matches] = await Promise.allSettled([
    tbaGet(`${base}/teams/simple`, apiKey, fetcher),
    tbaGet(`${base}/rankings`, apiKey, fetcher),
    tbaGet(`${base}/matches/simple`, apiKey, fetcher),
  ]);
  if (
    teams.status === "rejected" &&
    rankings.status === "rejected" &&
    matches.status === "rejected"
  ) {
    throw teams.reason;
  }
  return {
    fetchedAt: new Date().toISOString(),
    teams:
      teams.status === "fulfilled"
        ? parseTeams(teams.value)
        : (previous?.teams ?? []),
    rankings:
      rankings.status === "fulfilled"
        ? parseRankings(rankings.value)
        : (previous?.rankings ?? []),
    matches:
      matches.status === "fulfilled"
        ? parseEventMatches(matches.value)
        : (previous?.matches ?? []),
  };
}
