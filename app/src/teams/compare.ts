import type { PitEntry } from "../data/parse";
import { robotType } from "../match/robots";
import { parseTeamNumber } from "../now/myTeam";
import { allFields, type ScoutConfig } from "../scout/config";
import { displayValue, formatStat } from "../team/format";
import type { SeriesPoint } from "../team/stats";
import { reliableShare, signed, type TeamRow, tiedRows } from "./rows";

export const minCompare = 2;
export const maxCompare = 4;

export function parseCompare(param: string | null): number[] {
  const out: number[] = [];
  for (const part of (param ?? "").split(",")) {
    const team = parseTeamNumber(part);
    if (team !== null && !out.includes(team)) out.push(team);
  }
  return out.slice(0, maxCompare);
}

export const compareHref = (teams: number[]) =>
  teams.length === 0 ? "/teams/compare" : `/teams/compare?t=${teams.join(",")}`;

export interface MetricCell {
  team: number;
  text: string | null;
  best: boolean;
  series?: SeriesPoint[];
  error?: string;
}

export interface Metric {
  id: string;
  label: string;
  cells: MetricCell[];
  note?: string;
}

export interface MetricGroup {
  id: string;
  title: string;
  metrics: Metric[];
  note?: string;
}

export function bestFlags(
  values: (number | null)[],
  higherIsBetter: boolean,
): boolean[] {
  const present = values.flatMap((v) => (v === null ? [] : [v]));
  if (present.length < 2) return values.map(() => false);
  const best = higherIsBetter ? Math.max(...present) : Math.min(...present);
  if (present.every((v) => v === best)) return values.map(() => false);
  return values.map((v) => v === best);
}

interface NumberDef {
  id: string;
  label: string;
  value: (r: TeamRow) => number | null;
  text: (n: number, r: TeamRow) => string;
  higherIsBetter: boolean | null;
  error?: (r: TeamRow) => number | null;
}

const eventDefs: NumberDef[] = [
  {
    id: "epa",
    label: "EPA",
    value: (r) => r.epa,
    text: formatStat,
    higherIsBetter: true,
  },
  {
    id: "rank",
    label: "TBA rank",
    value: (r) => r.rank,
    text: String,
    higherIsBetter: false,
  },
];

const scoutedDefs: NumberDef[] = [
  {
    id: "matches",
    label: "Matches scouted",
    value: (r) => (r.matches > 0 ? r.matches : null),
    text: String,
    higherIsBetter: null,
  },
  {
    id: "total",
    label: "Scouted score",
    value: (r) => r.total,
    text: formatStat,
    higherIsBetter: true,
    error: (r) => r.totalSe,
  },
  {
    id: "floor",
    label: "Floor (bad day)",
    value: (r) => r.floor,
    text: formatStat,
    higherIsBetter: true,
  },
  {
    id: "reliability",
    label: "Reliability",
    value: reliableShare,
    text: (_, r) =>
      r.reliability ? `${r.reliability.ok} of ${r.reliability.of}` : "",
    higherIsBetter: true,
  },
  {
    id: "auto",
    label: "Auto",
    value: (r) => r.auto,
    text: formatStat,
    higherIsBetter: true,
    error: (r) => r.autoSe,
  },
  {
    id: "teleop",
    label: "Teleop",
    value: (r) => r.teleop,
    text: formatStat,
    higherIsBetter: true,
    error: (r) => r.teleopSe,
  },
  {
    id: "sd",
    label: "Consistency (SD)",
    value: (r) => r.sd,
    text: formatStat,
    higherIsBetter: false,
  },
  {
    id: "form",
    label: "Recent form",
    value: (r) => r.form,
    text: signed,
    higherIsBetter: true,
  },
  {
    id: "climb",
    label: "Best climb",
    value: (r) => (r.climb > 0 ? r.climb : null),
    text: (n) => `L${n}`,
    higherIsBetter: true,
  },
];

export function tieGroups(rows: TeamRow[]): number[][] {
  const groups: TeamRow[][] = [];
  for (const row of rows) {
    const linked = groups.filter((g) => g.some((o) => tiedRows(o, row)));
    const merged = [row, ...linked.flat()];
    for (const g of linked) groups.splice(groups.indexOf(g), 1);
    groups.push(merged);
  }
  return groups
    .filter((g) => g.length > 1)
    .map((g) => rows.filter((r) => g.includes(r)))
    .sort(
      (a, b) => rows.indexOf(a[0] as TeamRow) - rows.indexOf(b[0] as TeamRow),
    )
    .map((g) => g.map((r) => r.team));
}

export function tieNote(rows: TeamRow[]): string | undefined {
  const groups = tieGroups(rows);
  if (groups.length === 0) return undefined;
  return `Too close to call: ${groups.map((g) => g.join(", ")).join("; ")}.`;
}

function numberMetric(rows: TeamRow[], def: NumberDef): Metric {
  const values = rows.map(def.value);
  const flags =
    def.higherIsBetter === null
      ? values.map(() => false)
      : bestFlags(values, def.higherIsBetter);
  const note = def.id === "total" ? tieNote(rows) : undefined;
  return {
    id: def.id,
    label: def.label,
    cells: rows.map((r, i) => {
      const v = values[i] ?? null;
      const error = v === null ? null : (def.error?.(r) ?? null);
      return {
        team: r.team,
        text: v === null ? null : def.text(v, r),
        best: flags[i] ?? false,
        ...(error !== null && { error: `±${formatStat(error)}` }),
      };
    }),
    ...(note !== undefined && { note }),
  };
}

export function newestPit(entries: PitEntry[]): Map<number, PitEntry> {
  const out = new Map<number, PitEntry>();
  for (const entry of entries) {
    const held = out.get(entry.teamNumber);
    if (!held || entry.updatedAt.localeCompare(held.updatedAt) > 0) {
      out.set(entry.teamNumber, entry);
    }
  }
  return out;
}

const pitCodes: [code: string, label: string][] = [
  ["trenchFit", "Fits under trench"],
  ["shootsWhileMoving", "Shoots while moving"],
  ["climbLevel", "Climb (pit answer)"],
  ["maxFuelCapacity", "Fuel capacity"],
];

function pitMetrics(
  rows: TeamRow[],
  pit: Map<number, PitEntry>,
  config: ScoutConfig,
): Metric[] {
  const cell = (team: number, text: string): MetricCell => ({
    team,
    text: text === "" ? null : text,
    best: false,
  });
  const metrics: Metric[] = [
    {
      id: "pit-type",
      label: "Robot type",
      cells: rows.map((r) =>
        cell(r.team, robotType(pit.get(r.team) ?? null, config)),
      ),
    },
  ];
  const fields = allFields(config);
  for (const [code, label] of pitCodes) {
    const field = fields.find((f) => f.code === code);
    if (!field) continue;
    metrics.push({
      id: `pit-${code}`,
      label,
      cells: rows.map((r) =>
        cell(r.team, displayValue(field, pit.get(r.team)?.fieldValues[code])),
      ),
    });
  }
  return metrics;
}

export function buildMetrics(
  rows: TeamRow[],
  pit: Map<number, PitEntry>,
  pitConfig: ScoutConfig,
): MetricGroup[] {
  const missingPit = rows.filter((r) => !pit.has(r.team)).map((r) => r.team);
  return [
    {
      id: "event",
      title: "Event",
      metrics: [
        ...eventDefs.map((d) => numberMetric(rows, d)),
        {
          id: "record",
          label: "Record",
          cells: rows.map((r) => ({
            team: r.team,
            text: r.record === "" ? null : r.record,
            best: false,
          })),
        },
      ],
    },
    {
      id: "scouted",
      title: "Scouted",
      metrics: [
        ...scoutedDefs.map((d) => numberMetric(rows, d)),
        {
          id: "trend",
          label: "Match totals",
          cells: rows.map((r) => ({
            team: r.team,
            text: null,
            best: false,
            series: r.series,
          })),
        },
      ],
    },
    {
      id: "pit",
      title: "Pit",
      metrics: pitMetrics(rows, pit, pitConfig),
      ...(missingPit.length > 0 && {
        note: `No pit entry yet for ${missingPit.join(", ")}.`,
      }),
    },
  ];
}
