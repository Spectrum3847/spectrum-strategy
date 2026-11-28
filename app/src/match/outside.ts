import { tbaGet } from "../scout/tba";

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const num = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? v : null;
const point = (v: unknown) => num(v) ?? (isRecord(v) ? num(v.mean) : null);

const statboticsBase = "https://api.statbotics.io/v3";

export function parseEpa(raw: unknown): Record<number, number> {
  const out: Record<number, number> = {};
  if (!Array.isArray(raw)) return out;
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const team = num(item.team);
    if (team === null) continue;
    const total = isRecord(item.epa) ? point(item.epa.total_points) : null;
    if (team > 0 && total !== null) out[team] = total;
  }
  return out;
}

export async function fetchEpa(
  eventKey: string,
  fetcher: typeof fetch = fetch,
): Promise<Record<number, number>> {
  const response = await fetcher(
    `${statboticsBase}/team_events?event=${encodeURIComponent(eventKey)}&limit=100`,
    { headers: { Accept: "application/json" } },
  );
  if (!response.ok) throw new Error(`Statbotics answered ${response.status}`);
  return parseEpa(await response.json());
}

export interface Forecast {
  redScore: number;
  blueScore: number;
  redWin: number;
}

function fraction(raw: number): number {
  const value = raw > 1 ? raw / 100 : raw;
  return Math.min(1, Math.max(0, value));
}

export function parseForecasts(raw: unknown): Record<string, Forecast> {
  const out: Record<string, Forecast> = {};
  const levels = isRecord(raw) ? raw.match_predictions : null;
  if (!isRecord(levels)) return out;
  for (const level of Object.values(levels)) {
    if (!isRecord(level)) continue;
    for (const [key, value] of Object.entries(level)) {
      if (key === "" || !isRecord(value)) continue;
      const score = (alliance: unknown) =>
        isRecord(alliance) ? (num(alliance.score) ?? 0) : 0;
      const probability = fraction(num(value.prob) ?? 0);
      out[key] = {
        redScore: score(value.red),
        blueScore: score(value.blue),
        redWin:
          value.winning_alliance === "red"
            ? probability
            : value.winning_alliance === "blue"
              ? 1 - probability
              : 0.5,
      };
    }
  }
  return out;
}

export async function fetchForecasts(
  eventKey: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<Record<string, Forecast>> {
  return parseForecasts(
    await tbaGet(
      `/event/${encodeURIComponent(eventKey)}/predictions`,
      apiKey,
      fetcher,
    ),
  );
}
