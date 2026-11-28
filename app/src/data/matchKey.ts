export type CompLevel = "qm" | "ef" | "qf" | "sf" | "f";

export interface MatchRef {
  level: CompLevel;
  set: number;
  number: number;
}

const levelRank: Record<CompLevel, number> = {
  qm: 0,
  ef: 1,
  qf: 2,
  sf: 3,
  f: 4,
};

export function parseMatchKey(key: string): MatchRef | null {
  const m = /_(qm|ef|qf|sf|f)(\d+)(?:m(\d+))?$/i.exec(key.trim());
  if (!m) return null;
  const level = (m[1] ?? "").toLowerCase() as CompLevel;
  const first = Number(m[2]);
  if (m[3] !== undefined) return { level, set: first, number: Number(m[3]) };
  return level === "qm"
    ? { level, set: 1, number: first }
    : { level, set: first, number: 1 };
}

export function matchOrder(key: string): number {
  const ref = parseMatchKey(key);
  if (!ref) return Number.MAX_SAFE_INTEGER;
  return levelRank[ref.level] * 1e6 + ref.set * 1e3 + ref.number;
}

export function matchLabel(key: string): string {
  const ref = parseMatchKey(key);
  if (!ref) return key;
  if (ref.level === "qm") return `Q${ref.number}`;
  const level = ref.level.toUpperCase();
  if (ref.level === "f") return `${level}${ref.number}`;
  return ref.number > 1
    ? `${level}${ref.set} M${ref.number}`
    : `${level}${ref.set}`;
}

export const matchPath = (key: string) => `/matches/${encodeURIComponent(key)}`;
