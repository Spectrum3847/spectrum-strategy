import { isLead, type Role } from "../auth/roles";

export interface SeasonEvent {
  key: string;
  name: string;
  startDate: string | null;
  endDate: string | null;
  week: number | null;
  eventType: number | null;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const text = (v: unknown) => (typeof v === "string" && v !== "" ? v : null);
const int = (v: unknown) => (Number.isInteger(v) ? (v as number) : null);

const byStart = (a: SeasonEvent, b: SeasonEvent) =>
  (a.startDate ?? "9999").localeCompare(b.startDate ?? "9999") ||
  a.name.localeCompare(b.name);

export function parseEvents(raw: unknown): SeasonEvent[] {
  if (!Array.isArray(raw)) return [];
  const out: SeasonEvent[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const key = text(item.key);
    const name = text(item.name);
    if (key === null || name === null) continue;
    out.push({
      key,
      name,
      startDate: text(item.start_date),
      endDate: text(item.end_date),
      week: int(item.week),
      eventType: int(item.event_type),
    });
  }
  return out.sort(byStart);
}

export function weekLabel(event: SeasonEvent): string {
  if (event.week !== null) return `Week ${event.week + 1}`;
  if (event.eventType === 3 || event.eventType === 4) return "Championship";
  if (event.eventType === 99) return "Offseason";
  if (event.eventType === 100) return "Preseason";
  return "Other";
}

const dayNumber = (date: string): number | null => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(date);
  return m
    ? Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])) / 864e5
    : null;
};

const today = (now: Date) =>
  Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 864e5;

export function isEventNearby(
  event: Pick<SeasonEvent, "startDate" | "endDate">,
  now: Date,
  days = 3,
): boolean {
  const start = event.startDate === null ? null : dayNumber(event.startDate);
  const end = event.endDate === null ? start : dayNumber(event.endDate);
  if (start === null || end === null) return false;
  const day = today(now);
  return start <= day + days && end >= day - days;
}

export function filterEvents(
  events: SeasonEvent[],
  options: { query: string; showAll: boolean; now: Date },
): SeasonEvent[] {
  const query = options.query.trim().toLowerCase();
  return events.filter(
    (e) =>
      (options.showAll || query !== "" || isEventNearby(e, options.now)) &&
      (e.name.toLowerCase().includes(query) ||
        e.key.toLowerCase().includes(query)),
  );
}

export const canSetTeamEvent = (roles: Role[]) => isLead(roles);

export const activeEventPath = "appConfig/activeEvent";

export const activeEventDoc = (eventKey: string, now: Date) => ({
  eventKey,
  updatedAt: now.toISOString(),
});

export const seasonOf = (eventKey: string): number | null => {
  const year = Number(eventKey.slice(0, 4));
  return /^\d{4}/.test(eventKey) && year >= 1992 ? year : null;
};
