import { tbaGet } from "../scout/tba";

export interface AllianceFuel {
  matchKey: string;
  alliance: "red" | "blue";
  teams: number[];
  count: number;
  climbPoints?: number;
  foulPoints?: number;
  foulCount?: number;
  techFoulCount?: number;
  video?: string;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const teamNumber = (key: unknown) => {
  const n = Number(String(key).replace(/^frc/, ""));
  return Number.isInteger(n) && n > 0 ? n : null;
};

function pick(root: unknown, path: readonly string[]): unknown {
  let at = root;
  for (const step of path) {
    if (!isRecord(at)) return undefined;
    at = at[step];
  }
  return at;
}

const finite = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? v : null;

function climbPoints(breakdown: unknown): number | null {
  if (!isRecord(breakdown)) return null;
  const found = Object.entries(breakdown).flatMap(([key, value]) =>
    /tower|climb|endgame/i.test(key) &&
    /points/i.test(key) &&
    finite(value) !== null
      ? [{ key, value: value as number }]
      : [],
  );
  if (found.length === 0) return null;
  const total = found.find((f) => /^total/i.test(f.key));
  return total ? total.value : found.reduce((sum, f) => sum + f.value, 0);
}

function videoKey(raw: unknown): string | null {
  if (!Array.isArray(raw)) return null;
  for (const v of raw) {
    if (isRecord(v) && v.type === "youtube" && typeof v.key === "string") {
      return v.key;
    }
  }
  return null;
}

export function parseAllianceCounts(
  raw: unknown,
  path: readonly string[],
): AllianceFuel[] {
  if (!Array.isArray(raw)) return [];
  const out: AllianceFuel[] = [];
  for (const m of raw) {
    if (!isRecord(m) || typeof m.key !== "string") continue;
    const alliances = isRecord(m.alliances) ? m.alliances : {};
    const breakdown = isRecord(m.score_breakdown) ? m.score_breakdown : {};
    for (const side of ["red", "blue"] as const) {
      const count = pick(breakdown[side], path);
      if (typeof count !== "number" || !Number.isFinite(count)) continue;
      const alliance = alliances[side];
      const keys =
        isRecord(alliance) && Array.isArray(alliance.team_keys)
          ? alliance.team_keys
          : [];
      const own = breakdown[side];
      const detail = isRecord(own) ? own : {};
      const extra = {
        climbPoints: climbPoints(own),
        foulPoints: finite(detail.foulPoints),
        foulCount: finite(detail.foulCount),
        techFoulCount: finite(detail.techFoulCount),
        video: videoKey(m.videos),
      };
      out.push({
        matchKey: m.key,
        alliance: side,
        teams: keys.map(teamNumber).filter((n): n is number => n !== null),
        count: Math.trunc(count),
        ...Object.fromEntries(
          Object.entries(extra).filter(([, value]) => value !== null),
        ),
      });
    }
  }
  return out;
}

export async function fetchAllianceCounts(
  eventKey: string,
  apiKey: string,
  path: readonly string[],
  fetcher: typeof fetch = fetch,
): Promise<AllianceFuel[]> {
  const raw = await tbaGet(
    `/event/${encodeURIComponent(eventKey)}/matches`,
    apiKey,
    fetcher,
  );
  return parseAllianceCounts(raw, path);
}
