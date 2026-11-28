import { matchOrder } from "../data/matchKey";
import {
  allFields,
  effectiveDefault,
  labelForStored,
  normalizeStation,
  type ScoutConfig,
  type ScoutField,
  selectedKeys,
  storedCounter,
  type Values,
} from "../scout/config";

export interface ExportEntry {
  tbaMatchKey: string | null;
  teamNumber: number;
  scoutName: string;
  createdAt?: string;
  updatedAt: string;
  fieldValues: Values;
}

export interface ExportOptions {
  hideNames: boolean;
  includeComments: boolean;
}

const answerTypes: ReadonlySet<string> = new Set([
  "counter",
  "multiCounter",
  "boolean",
  "select",
]);

const nameField = /scouter|scout name|\bname\b|e-?mail/i;

export const answerFields = (config: ScoutConfig) =>
  allFields(config).filter((f) => answerTypes.has(f.type));

export const commentFields = (config: ScoutConfig) =>
  allFields(config).filter(
    (f) =>
      (f.type === "text" || f.type === "longText") &&
      !nameField.test(`${f.title} ${f.code}`),
  );

const formulaStart = /^[=+\-@\t\r]/;
const plainNumber = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;

export function csvCell(value: string): string {
  let cell = value;
  if (formulaStart.test(cell) && !plainNumber.test(cell.trim())) {
    cell = `'${cell}`;
  }
  return /[,"\r\n]/.test(cell) ? `"${cell.replaceAll('"', '""')}"` : cell;
}

export const csvLine = (cells: string[]) => cells.map(csvCell).join(",");

const text = (v: unknown) => (v === null || v === undefined ? "" : String(v));

export function displayValue(field: ScoutField, stored: unknown): string {
  if (stored === null || stored === undefined) return "";
  if (field.type === "select") return labelForStored(field, stored);
  if (field.type === "checkboxSelect") {
    const keys = selectedKeys(stored);
    if (keys.length === 0) return String(stored);
    const labels = new Map(field.choices ?? []);
    return keys.map((k) => labels.get(k) ?? k).join(", ");
  }
  return String(stored);
}

export function isNoShowAnswer(field: ScoutField, values: Values): boolean {
  if (field.type !== "select") return false;
  const label = labelForStored(field, values[field.code]);
  return label.toLowerCase().replace(/[^a-z]/g, "") === "noshow";
}

export function isContradictedNoShow(
  field: ScoutField,
  values: Values,
  config: ScoutConfig,
): boolean {
  if (!isNoShowAnswer(field, values)) return false;
  for (const other of allFields(config)) {
    const value = values[other.code];
    if (value === null || value === undefined) continue;
    if (
      other.type === "counter" ||
      other.type === "multiCounter" ||
      other.type === "range"
    ) {
      const count = storedCounter(value);
      const initial = storedCounter(effectiveDefault(other)) ?? 0;
      if (count !== null && count !== initial) return true;
    } else if (other.type === "boolean") {
      const checked = value === true || String(value) === "true";
      if (checked !== (effectiveDefault(other) === true)) return true;
    }
  }
  return false;
}

export function stationOfEntry(values: Values): string {
  let found: string | null = null;
  for (const value of Object.values(values)) {
    let station: string | null = null;
    if (typeof value === "string") station = normalizeStation(value);
    else if (typeof value === "object" && value !== null) {
      const position = (value as Record<string, unknown>).robotPosition;
      if (typeof position === "string") station = normalizeStation(position);
    }
    if (station === null) continue;
    if (found !== null && found !== station) return "";
    found ??= station;
  }
  return found ?? "";
}

const matchOf = (e: ExportEntry) => e.tbaMatchKey ?? "";

function ordered(entries: ExportEntry[]): ExportEntry[] {
  return entries
    .map((e) => ({ e, station: stationOfEntry(e.fieldValues) }))
    .sort(
      (a, b) =>
        matchOrder(matchOf(a.e)) - matchOrder(matchOf(b.e)) ||
        matchOf(a.e).localeCompare(matchOf(b.e)) ||
        a.station.localeCompare(b.station) ||
        a.e.teamNumber - b.e.teamNumber ||
        a.e.updatedAt.localeCompare(b.e.updatedAt),
    )
    .map((x) => x.e);
}

export function scoutAliases() {
  const seen = new Map<string, string>();
  return (name: string) => {
    const key = name.trim().toLowerCase();
    if (key === "") return "";
    let alias = seen.get(key);
    if (alias === undefined) {
      alias = `Scout ${seen.size + 1}`;
      seen.set(key, alias);
    }
    return alias;
  };
}

export function buildScoutCsv(
  config: ScoutConfig,
  entries: ExportEntry[],
  eventKey: string,
  options: ExportOptions,
): string {
  const answers = answerFields(config);
  const comments = options.includeComments ? commentFields(config) : [];
  const alias = scoutAliases();
  const header = [
    "Event",
    "Match",
    "Team",
    "Station",
    "Created (UTC)",
    "Updated (UTC)",
    ...answers.map((f) => f.title),
    "Scout",
    ...comments.map((f) => f.title),
  ];
  const lines = [csvLine(header)];
  for (const entry of ordered(entries)) {
    const values = entry.fieldValues;
    lines.push(
      csvLine([
        eventKey,
        matchOf(entry),
        String(entry.teamNumber),
        stationOfEntry(values),
        entry.createdAt ?? "",
        entry.updatedAt,
        ...answers.map((f) =>
          isContradictedNoShow(f, values, config)
            ? ""
            : displayValue(f, values[f.code]),
        ),
        options.hideNames ? alias(entry.scoutName) : entry.scoutName.trim(),
        ...comments.map((f) => text(values[f.code]).trim()),
      ]),
    );
  }
  return lines.join("\r\n");
}

export function exportFileName(eventKey: string): string {
  const slug = eventKey
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return slug === "" ? "scout-entries.csv" : `${slug}-scout-entries.csv`;
}
