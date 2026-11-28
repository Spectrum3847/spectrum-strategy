import { reliableShare, type TeamRow } from "./rows";

export type SortKey =
  | "epa"
  | "rank"
  | "total"
  | "floor"
  | "auto"
  | "teleop"
  | "sd"
  | "reliable"
  | "form"
  | "climb"
  | "matches"
  | "number";

export interface Sort {
  key: SortKey;
  reversed: boolean;
}

export const defaultSort: Sort = { key: "epa", reversed: false };

interface KeyDef {
  label: string;
  value: (r: TeamRow) => number | null;
  descending: boolean;
}

export const sortKeys: Record<SortKey, KeyDef> = {
  epa: { label: "EPA", value: (r) => r.epa, descending: true },
  rank: { label: "TBA rank", value: (r) => r.rank, descending: false },
  total: { label: "Scouted score", value: (r) => r.total, descending: true },
  floor: { label: "Floor (bad day)", value: (r) => r.floor, descending: true },
  auto: { label: "Auto", value: (r) => r.auto, descending: true },
  teleop: { label: "Teleop", value: (r) => r.teleop, descending: true },
  sd: { label: "Consistency", value: (r) => r.sd, descending: false },
  reliable: { label: "Reliability", value: reliableShare, descending: true },
  form: { label: "Recent form", value: (r) => r.form, descending: true },
  climb: {
    label: "Best climb",
    value: (r) => (r.climb > 0 ? r.climb : null),
    descending: true,
  },
  matches: {
    label: "Matches scouted",
    value: (r) => (r.matches > 0 ? r.matches : null),
    descending: true,
  },
  number: { label: "Team number", value: (r) => r.team, descending: false },
};

export const sortKeyOrder = Object.keys(sortKeys) as SortKey[];

function missingLast(
  a: number | null,
  b: number | null,
  descending: boolean,
): number {
  if (a === null && b === null) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  return descending ? b - a : a - b;
}

const byDefault = (a: TeamRow, b: TeamRow) =>
  missingLast(a.epa, b.epa, true) ||
  missingLast(a.rank, b.rank, false) ||
  a.team - b.team;

export function defaultPlaces(rows: TeamRow[]): Map<number, number> {
  return new Map([...rows].sort(byDefault).map((r, i) => [r.team, i + 1]));
}

export function sortRows(rows: TeamRow[], sort: Sort): TeamRow[] {
  const def = sortKeys[sort.key];
  const flip = def.descending !== sort.reversed;
  return [...rows].sort(
    (a, b) => missingLast(def.value(a), def.value(b), flip) || byDefault(a, b),
  );
}

export function orderNotice(
  rows: TeamRow[],
  epaStatus: "none" | "loading" | "ready" | "failed",
): string | null {
  const listed = rows.filter((r) => r.listed);
  if (listed.length === 0) return null;
  if (listed.some((r) => r.epa !== null)) {
    const missing = listed.filter((r) => r.epa === null).length;
    return missing === 0
      ? null
      : `${missing} ${missing === 1 ? "team has" : "teams have"} no EPA and follow the rest in TBA rank order.`;
  }
  const order = rows.some((r) => r.rank !== null)
    ? "TBA rank"
    : "team number, because TBA has posted no rankings yet";
  switch (epaStatus) {
    case "ready":
      return `Statbotics has no EPA for this event, which is common offseason. Teams are ordered by ${order}.`;
    case "failed":
      return `Statbotics could not be reached, so there is no EPA. Teams are ordered by ${order}.`;
    default:
      return `Waiting for Statbotics. Teams are ordered by ${order} for now.`;
  }
}

export function searchRows(rows: TeamRow[], query: string): TeamRow[] {
  const q = query.trim().toLowerCase();
  if (q === "") return rows;
  const digits = q.replace(/^frc/, "");
  return rows.filter(
    (r) =>
      String(r.team).startsWith(digits) || r.nickname.toLowerCase().includes(q),
  );
}
