export interface UsageCount {
  name: string;
  count: number;
}

export interface UsageDay {
  date: string;
  count: number;
}

export interface UsageRollup {
  updatedAt: Date | null;
  windowDays: number;
  eventsCounted: number;
  deviceCount: number;
  tabs: UsageCount[];
  platforms: UsageCount[];
  appVersions: UsageCount[];
  daily: UsageDay[];
}

const asInt = (value: unknown): number => {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.round(value);
  }
  if (typeof value === "string") {
    const n = Number.parseInt(value, 10);
    return Number.isNaN(n) ? 0 : n;
  }
  return 0;
};

function rows<T>(
  value: unknown,
  key: "name" | "date",
  make: (label: string, count: number) => T,
): T[] {
  if (!Array.isArray(value)) return [];
  const out: T[] = [];
  for (const row of value) {
    if (typeof row !== "object" || row === null) continue;
    const entry = row as Record<string, unknown>;
    const label = entry[key];
    if (typeof label === "string" && label !== "") {
      out.push(make(label, asInt(entry.count)));
    }
  }
  return out;
}

export function parseRollup(data: Record<string, unknown>): UsageRollup {
  const stamp =
    typeof data.updatedAt === "string" ? new Date(data.updatedAt) : null;
  const count = (name: string, n: number): UsageCount => ({ name, count: n });
  return {
    updatedAt: stamp && !Number.isNaN(stamp.getTime()) ? stamp : null,
    windowDays: asInt(data.windowDays),
    eventsCounted: asInt(data.eventsCounted),
    deviceCount: asInt(data.deviceCount),
    tabs: rows(data.tabs, "name", count),
    platforms: rows(data.platforms, "name", count),
    appVersions: rows(data.appVersions, "name", count),
    daily: rows(data.daily, "date", (date, n) => ({ date, count: n })),
  };
}

export const isEmptyRollup = (r: UsageRollup) => r.eventsCounted === 0;

export const busiestDay = (days: UsageDay[]) =>
  days.reduce((max, d) => Math.max(max, d.count), 0);

export function freshness(updatedAt: Date | null): string {
  if (!updatedAt) return "Last updated: unknown.";
  const p = (n: number) => String(n).padStart(2, "0");
  const stamp = `${updatedAt.getFullYear()}-${p(updatedAt.getMonth() + 1)}-${p(updatedAt.getDate())} ${p(updatedAt.getHours())}:${p(updatedAt.getMinutes())}`;
  return `Rolled up ${stamp}. The job runs once a day.`;
}
