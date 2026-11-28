import type { ScheduledMatch } from "../scout/schedule";

const levelOrder = ["qm", "ef", "qf", "sf", "f"];
const levelName: Record<string, string> = {
  ef: "Eighthfinal",
  qf: "Quarterfinal",
  sf: "Semifinal",
};

interface Position {
  level: string;
  set: number;
  number: number;
}

function position(m: ScheduledMatch): Position {
  const parsed = /_(qm|ef|qf|sf|f)(\d+)(?:m(\d+))?$/.exec(m.key.toLowerCase());
  if (parsed?.[3] !== undefined) {
    return {
      level: parsed[1] ?? m.compLevel,
      set: Number(parsed[2]),
      number: Number(parsed[3]),
    };
  }
  return { level: m.compLevel, set: 1, number: m.matchNumber };
}

const rank = (level: string) => {
  const i = levelOrder.indexOf(level);
  return i === -1 ? levelOrder.length : i;
};

export function compareMatches(a: ScheduledMatch, b: ScheduledMatch): number {
  const pa = position(a);
  const pb = position(b);
  return (
    rank(pa.level) - rank(pb.level) ||
    pa.set - pb.set ||
    pa.number - pb.number ||
    a.key.localeCompare(b.key)
  );
}

export function matchLabel(m: ScheduledMatch): string {
  const p = position(m);
  if (p.level === "qm") return `Q${p.number}`;
  if (p.level === "f") return `Final ${p.number}`;
  const name = levelName[p.level] ?? p.level.toUpperCase();
  return p.number > 1
    ? `${name} ${p.set} match ${p.number}`
    : `${name} ${p.set}`;
}

export const isPlayed = (m: ScheduledMatch) =>
  (m.redScore ?? -1) >= 0 && (m.blueScore ?? -1) >= 0;

export interface MatchTime {
  at: number;
  kind: "predicted" | "scheduled";
}

export function matchTime(m: ScheduledMatch): MatchTime | null {
  if (typeof m.predictedTime === "number") {
    return { at: m.predictedTime, kind: "predicted" };
  }
  if (typeof m.time === "number") return { at: m.time, kind: "scheduled" };
  return null;
}

export interface TimeOptions {
  locale?: string;
  timeZone?: string;
}

export function formatTime(
  epochSeconds: number,
  now: Date,
  { locale, timeZone }: TimeOptions = {},
): string {
  const at = new Date(epochSeconds * 1000);
  const day = new Intl.DateTimeFormat(locale, {
    year: "numeric",
    month: "numeric",
    day: "numeric",
    timeZone,
  });
  const clock = new Intl.DateTimeFormat(locale, {
    hour: "numeric",
    minute: "2-digit",
    timeZone,
  })
    .format(at)
    .replace(/ /g, " ");
  if (day.format(at) === day.format(now)) return clock;
  const weekday = new Intl.DateTimeFormat(locale, {
    weekday: "short",
    timeZone,
  }).format(at);
  return `${weekday} ${clock}`;
}

export function timeLine(
  m: ScheduledMatch,
  now: Date,
  options?: TimeOptions,
): string | null {
  const t = matchTime(m);
  if (!t) return null;
  const at = formatTime(t.at, now, options);
  if (t.kind === "scheduled") return `Scheduled ${at}`;
  if (typeof m.time === "number" && m.time !== t.at) {
    return `Predicted ${at} (scheduled ${formatTime(m.time, now, options)})`;
  }
  return `Predicted ${at}`;
}

export function awayText(away: number): string {
  if (away === 0) return "Up next";
  return away === 1 ? "1 match away" : `${away} matches away`;
}
