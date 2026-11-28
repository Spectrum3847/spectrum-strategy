import { readCache, writeCache } from "../data/cache";
import { teamKey } from "../data/tbaKey";
import { tbaGet } from "../scout/tba";

export interface SeasonRow {
  year: number;
  wins: number;
  losses: number;
  ties: number;
  epaRank: number | null;
  epaRankTeamCount: number | null;
  unitless: number | null;
  norm: number | null;
  totalPoints: number | null;
  autoPoints: number | null;
  teleopPoints: number | null;
  endgamePoints: number | null;
}

export interface EventRow {
  event: string;
  eventName: string;
  year: number;
  wins: number;
  losses: number;
  ties: number;
  rank: number | null;
  numTeams: number | null;
  totalPoints: number | null;
  autoPoints: number | null;
  teleopPoints: number | null;
  endgamePoints: number | null;
}

export interface AwardRow {
  name: string;
  eventKey: string;
  year: number;
  isWinOrFinalist: boolean;
}

export interface Placement {
  eventKey: string;
  allianceNumber: number;
  pickIndex: number;
  roundReached: string;
}

export interface TeamHistory {
  seasons: SeasonRow[];
  events: EventRow[];
  awards: AwardRow[];
  alliances: Placement[];
}

export const emptyHistory: TeamHistory = {
  seasons: [],
  events: [],
  awards: [],
  alliances: [],
};

export const seasonCount = 2;
export const freshMs = 6 * 3_600_000;

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const num = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? v : null;
const point = (v: unknown) => num(v) ?? (isRecord(v) ? num(v.mean) : null);
const int = (v: unknown) => {
  const n = num(v);
  return n === null ? null : Math.trunc(n);
};
const str = (v: unknown) => (typeof v === "string" ? v : "");
const rec = (v: unknown): Raw => (isRecord(v) ? v : {});

function epaOf(raw: unknown) {
  const epa = rec(raw);
  const breakdown = rec(epa.breakdown);
  return {
    totalPoints: point(epa.total_points),
    unitless: point(epa.unitless),
    norm: point(epa.norm),
    autoPoints: point(breakdown.auto_points),
    teleopPoints: point(breakdown.teleop_points),
    endgamePoints: point(breakdown.endgame_points),
  };
}

export function parseSeasons(raw: unknown): SeasonRow[] {
  if (!Array.isArray(raw)) return [];
  const rows: SeasonRow[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const record = rec(item.record);
    const total = rec(rec(rec(item.epa).ranks).total);
    const {
      unitless,
      norm,
      totalPoints,
      autoPoints,
      teleopPoints,
      endgamePoints,
    } = epaOf(item.epa);
    rows.push({
      year: int(item.year) ?? 0,
      wins: int(record.wins) ?? 0,
      losses: int(record.losses) ?? 0,
      ties: int(record.ties) ?? 0,
      epaRank: int(total.rank),
      epaRankTeamCount: int(total.team_count),
      unitless,
      norm,
      totalPoints,
      autoPoints,
      teleopPoints,
      endgamePoints,
    });
  }
  return rows.sort((a, b) => b.year - a.year);
}

export function parseTeamEvents(raw: unknown): EventRow[] {
  if (!Array.isArray(raw)) return [];
  const rows: EventRow[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const record = rec(item.record);
    const total = rec(record.total);
    const qual = rec(record.qual);
    const { totalPoints, autoPoints, teleopPoints, endgamePoints } = epaOf(
      item.epa,
    );
    rows.push({
      event: str(item.event),
      eventName: str(item.event_name),
      year: int(item.year) ?? 0,
      wins: int(total.wins) ?? 0,
      losses: int(total.losses) ?? 0,
      ties: int(total.ties) ?? 0,
      rank: int(qual.rank),
      numTeams: int(qual.num_teams),
      totalPoints,
      autoPoints,
      teleopPoints,
      endgamePoints,
    });
  }
  return rows.sort((a, b) => a.event.localeCompare(b.event));
}

export function parseAwards(raw: unknown): AwardRow[] {
  if (!Array.isArray(raw)) return [];
  const rows: AwardRow[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const recipients = Array.isArray(item.recipient_list)
      ? item.recipient_list
      : [];
    const individual = recipients.some(
      (r) => isRecord(r) && typeof r.awardee === "string" && r.awardee !== "",
    );
    if (individual) continue;
    const type = int(item.award_type);
    rows.push({
      name: str(item.name),
      eventKey: str(item.event_key),
      year: int(item.year) ?? 0,
      isWinOrFinalist: type === 1 || type === 2,
    });
  }
  return rows;
}

export function parsePlacement(
  raw: unknown,
  eventKey: string,
  team: number,
): Placement | null {
  if (!Array.isArray(raw)) return null;
  const teamKey = `frc${team}`;
  for (const [index, alliance] of raw.entries()) {
    if (!isRecord(alliance) || !Array.isArray(alliance.picks)) continue;
    const pick = alliance.picks.indexOf(teamKey);
    if (pick < 0) continue;
    return {
      eventKey,
      allianceNumber: index + 1,
      pickIndex: pick,
      roundReached: str(rec(alliance.status).level),
    };
  }
  return null;
}

const statboticsBase = "https://api.statbotics.io/v3";

async function statbotics(
  path: string,
  fetcher: typeof fetch,
): Promise<unknown> {
  const response = await fetcher(`${statboticsBase}${path}`, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error(`Statbotics answered ${response.status}`);
  return response.json();
}

async function orEmpty<T>(load: () => Promise<T[]>): Promise<T[]> {
  try {
    return await load();
  } catch {
    return [];
  }
}

export async function fetchHistory(
  team: number,
  apiKey: string | null,
  fetcher: typeof fetch = fetch,
): Promise<TeamHistory> {
  const all = parseSeasons(
    await statbotics(`/team_years?team=${team}&limit=100`, fetcher),
  );
  const seasons = all.slice(0, seasonCount);
  const years = seasons.map((s) => s.year);

  const events = (
    await Promise.all(
      years.map((year) =>
        orEmpty(async () =>
          parseTeamEvents(
            await statbotics(
              `/team_events?team=${team}&year=${year}&limit=1000`,
              fetcher,
            ),
          ),
        ),
      ),
    )
  )
    .flat()
    .sort((a, b) => b.year - a.year);

  if (apiKey === null) return { seasons, events, awards: [], alliances: [] };

  const awards = (
    await Promise.all(
      years.map((year) =>
        orEmpty(async () =>
          parseAwards(
            await tbaGet(`/team/frc${team}/awards/${year}`, apiKey, fetcher),
          ),
        ),
      ),
    )
  )
    .flat()
    .sort((a, b) => b.year - a.year);

  const placements = await Promise.all(
    events.map((e) =>
      orEmpty(async () => {
        const found = parsePlacement(
          await tbaGet(
            `/event/${encodeURIComponent(e.event)}/alliances`,
            apiKey,
            fetcher,
          ),
          e.event,
          team,
        );
        return found ? [found] : [];
      }),
    ),
  );
  return { seasons, events, awards, alliances: placements.flat() };
}

interface Stored {
  fetchedAt: number;
  history: TeamHistory;
}

export async function loadHistory(
  team: number,
  nowMs: number = Date.now(),
  fetcher: typeof fetch = fetch,
): Promise<TeamHistory> {
  const key = `ss.history.${team}`;
  const stored = readCache<Stored>(key);
  if (stored && nowMs - stored.fetchedAt < freshMs) return stored.history;
  try {
    const history = await fetchHistory(team, await teamKey(), fetcher);
    writeCache(key, { fetchedAt: nowMs, history } satisfies Stored);
    return history;
  } catch {
    return stored?.history ?? emptyHistory;
  }
}
