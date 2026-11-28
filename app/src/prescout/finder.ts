import { tbaGet } from "../scout/tba";

export type PrescoutMatchType = "qual" | "playoff" | "final";

export interface PrescoutMatch {
  matchKey: string;
  eventKey: string;
  eventName: string;
  matchType: PrescoutMatchType;
  number: string;
  isPlayoff: boolean;
  videoUrl: string;
}

export interface PrescoutPlan {
  fetchedAt: string;
  matches: PrescoutMatch[];
  note: string | null;
}

export const quals = 3;
export const playoffs = 2;
export const wanted = quals + playoffs;
const maxEvents = 6;

interface Video {
  type: string;
  key: string;
}
interface TbaEventInfo {
  key: string;
  name: string;
  startDate: string | null;
  endDate: string | null;
  preseason: boolean;
}
interface TbaTeamMatch {
  key: string;
  compLevel: string;
  matchNumber: number;
  setNumber: number;
  played: boolean;
  time: number | null;
  actualTime: number | null;
  videos: Video[];
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : "");
const num = (v: unknown, fallback: number) =>
  typeof v === "number" && Number.isFinite(v) ? v : fallback;
const seconds = (v: unknown) => (typeof v === "number" && v > 0 ? v : null);

export function parseTeamEvents(raw: unknown): TbaEventInfo[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord).map((e) => ({
    key: str(e.key),
    name: str(e.name),
    startDate: typeof e.start_date === "string" ? e.start_date : null,
    endDate: typeof e.end_date === "string" ? e.end_date : null,
    preseason: e.event_type === 100,
  }));
}

const score = (alliance: unknown) =>
  isRecord(alliance) &&
  typeof alliance.score === "number" &&
  alliance.score >= 0
    ? alliance.score
    : null;

export function parseTeamMatches(raw: unknown): TbaTeamMatch[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter(isRecord).map((m) => {
    const alliances = isRecord(m.alliances) ? m.alliances : {};
    return {
      key: str(m.key),
      compLevel: typeof m.comp_level === "string" ? m.comp_level : "qm",
      matchNumber: num(m.match_number, 0),
      setNumber: num(m.set_number, 1),
      played: score(alliances.red) !== null && score(alliances.blue) !== null,
      time: seconds(m.time),
      actualTime: seconds(m.actual_time),
      videos: Array.isArray(m.videos)
        ? m.videos
            .filter(isRecord)
            .map((v) => ({ type: str(v.type), key: str(v.key) }))
        : [],
    };
  });
}

const videoId = (v: Video) => v.key.split("?")[0] ?? "";
const watchable = (v: Video) => v.type === "youtube" && videoId(v) !== "";

const levels = ["qm", "ef", "qf", "sf", "f"];
const order = (m: TbaTeamMatch) =>
  (levels.indexOf(m.compLevel) * 100 + m.setNumber) * 1000 + m.matchNumber;

function newestFirst(a: TbaTeamMatch, b: TbaTeamMatch): number {
  const at = a.actualTime ?? a.time;
  const bt = b.actualTime ?? b.time;
  if (at !== null && bt !== null && at !== bt) return bt - at;
  return order(b) - order(a);
}

const clamp = (want: number, room: number, available: number) =>
  want <= 0 || room <= 0 ? 0 : Math.min(want, room, available);

function numberOf(m: TbaTeamMatch): string {
  if (m.compLevel === "qm" || m.compLevel === "f") return String(m.matchNumber);
  if (m.compLevel === "sf" && m.matchNumber === 1) return String(m.setNumber);
  return `${m.setNumber}-${m.matchNumber}`;
}

function videoUrlOf(v: Video): string {
  const [id, query] = v.key.split("?");
  const start = query ? /(?:^|&)t=(\d+)/.exec(query)?.[1] : undefined;
  return `https://www.youtube.com/watch?v=${id}${start ? `&t=${start}` : ""}`;
}

function toMatch(m: TbaTeamMatch, event: TbaEventInfo): PrescoutMatch {
  const video = m.videos.find(watchable) as Video;
  return {
    matchKey: m.key,
    eventKey: event.key,
    eventName: event.name,
    matchType:
      m.compLevel === "qm" ? "qual" : m.compLevel === "f" ? "final" : "playoff",
    number: numberOf(m),
    isPlayoff: m.compLevel !== "qm",
    videoUrl: videoUrlOf(video),
  };
}

const count = (n: number, noun: string) => `${n} ${noun}${n === 1 ? "" : "s"}`;

interface Used {
  name: string;
  quals: number;
  playoffs: number;
}

function noteFor(
  team: number,
  year: number,
  found: number,
  skipped: string[],
  used: Used[],
): string | null {
  if (found === 0) {
    return `The Blue Alliance has no match videos for ${team} in ${year} yet.`;
  }
  const first = used[0] as Used;
  const parts: string[] = [];
  if (skipped.length > 0)
    parts.push(`${skipped.join(", ")} had no match videos`);
  if (first.playoffs === 0 && first.quals > quals) {
    parts.push(
      `${first.name}: no playoff videos, so ${first.quals} quals instead`,
    );
  } else if (first.quals !== quals || first.playoffs !== playoffs) {
    parts.push(
      `${first.name}: ${count(first.quals, "qual")} and ${count(first.playoffs, "playoff")}`,
    );
  }
  if (used.length > 1) {
    parts.push(
      `the rest from ${used
        .slice(1)
        .map((u) => u.name)
        .join(", ")}`,
    );
  }
  if (found < wanted)
    parts.push(`only ${found} of ${wanted} matches have video`);
  return parts.length === 0 ? null : parts.join("; ");
}

const isoDate = (d: Date) =>
  `${String(d.getFullYear()).padStart(4, "0")}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export interface Source {
  teamEvents(): Promise<unknown>;
  teamMatches(eventKey: string): Promise<unknown>;
}

export async function planMatches(
  team: number,
  year: number,
  excludeEventKey: string,
  source: Source,
  now: Date = new Date(),
): Promise<PrescoutPlan> {
  const today = isoDate(now);
  const fetchedAt = now.toISOString();
  const events = parseTeamEvents(await source.teamEvents())
    .filter(
      (e) =>
        e.key !== excludeEventKey &&
        !e.preseason &&
        (e.startDate === null || e.startDate <= today),
    )
    .sort((a, b) => (b.endDate ?? "").localeCompare(a.endDate ?? ""));
  if (events.length === 0) {
    return {
      fetchedAt,
      matches: [],
      note: `The Blue Alliance has no ${year} events for ${team} yet.`,
    };
  }

  const picked: PrescoutMatch[] = [];
  const skipped: string[] = [];
  const used: Used[] = [];
  for (const event of events.slice(0, maxEvents)) {
    if (picked.length >= wanted) break;
    const matches = parseTeamMatches(await source.teamMatches(event.key));
    const withVideo = matches
      .filter((m) => m.played && m.videos.some(watchable))
      .sort(newestFirst);
    if (withVideo.length === 0) {
      if (matches.some((m) => m.played)) skipped.push(event.name);
      continue;
    }
    const q = withVideo.filter((m) => m.compLevel === "qm");
    const p = withVideo.filter((m) => m.compLevel !== "qm");
    const need = wanted - picked.length;
    const haveP = picked.filter((m) => m.isPlayoff).length;
    const haveQ = picked.length - haveP;
    let takeP = clamp(playoffs - haveP, need, p.length);
    let takeQ = clamp(quals - haveQ, need - takeP, q.length);
    if (takeP + takeQ < need) takeQ = clamp(need - takeP, need, q.length);
    if (takeP + takeQ < need) takeP = clamp(need - takeQ, need, p.length);

    used.push({ name: event.name, quals: takeQ, playoffs: takeP });
    const take = [...q.slice(0, takeQ), ...p.slice(0, takeP)]
      .sort(newestFirst)
      .reverse();
    for (const m of take) picked.push(toMatch(m, event));
  }
  return {
    fetchedAt,
    matches: picked,
    note: noteFor(team, year, picked.length, skipped, used),
  };
}

const lenientFetch: typeof fetch = async (input, init) => {
  const response = await fetch(input, init);
  return response.status === 404 ? new Response("[]") : response;
};

export function tbaSource(team: number, year: number, apiKey: string): Source {
  return {
    teamEvents: () =>
      tbaGet(`/team/frc${team}/events/${year}/simple`, apiKey, lenientFetch),
    teamMatches: (eventKey) =>
      tbaGet(
        `/team/frc${team}/event/${encodeURIComponent(eventKey)}/matches`,
        apiKey,
        lenientFetch,
      ),
  };
}
