import type { TeamRow } from "./rows";

export type Heat = 0 | 1 | 2 | 3 | 4;

const minTeams = 4;

export function heatLevels(
  values: (number | null)[],
  higherIsBetter: boolean,
): Heat[] {
  const present = values.flatMap((v) => (v === null ? [] : [v]));
  const none = values.map((): Heat => 0);
  if (
    present.length < minTeams ||
    Math.min(...present) === Math.max(...present)
  ) {
    return none;
  }
  const signed = (v: number) => (higherIsBetter ? v : -v);
  return values.map((v): Heat => {
    if (v === null) return 0;
    const below = present.filter((p) => signed(p) < signed(v)).length;
    const equal = present.filter((p) => signed(p) === signed(v)).length;
    const place = (below + (equal - 1) / 2) / (present.length - 1);
    return Math.min(4, Math.floor(place * 5)) as Heat;
  });
}

export type HeatKey =
  | "epa"
  | "total"
  | "floor"
  | "auto"
  | "teleop"
  | "sd"
  | "form";

export const heatKeys: Record<HeatKey, { higherIsBetter: boolean }> = {
  epa: { higherIsBetter: true },
  total: { higherIsBetter: true },
  floor: { higherIsBetter: true },
  auto: { higherIsBetter: true },
  teleop: { higherIsBetter: true },
  sd: { higherIsBetter: false },
  form: { higherIsBetter: true },
};

export type HeatMap = Record<HeatKey, Map<number, Heat>>;

export function heatMap(rows: TeamRow[]): HeatMap {
  const out = {} as HeatMap;
  for (const key of Object.keys(heatKeys) as HeatKey[]) {
    const levels = heatLevels(
      rows.map((r) => r[key]),
      heatKeys[key].higherIsBetter,
    );
    out[key] = new Map(rows.map((r, i) => [r.team, levels[i] ?? 0]));
  }
  return out;
}
