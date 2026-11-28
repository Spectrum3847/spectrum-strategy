import {
  allFields,
  effectiveDefault,
  type ScoutConfig,
  type ScoutField,
  selectedKeys,
  type Values,
} from "./config";

export interface PayloadColumn {
  code: string;
  field: ScoutField;
  derived: "count" | "times" | null;
}

export function payloadColumns(config: ScoutConfig): PayloadColumn[] {
  const columns: PayloadColumn[] = [];
  for (const field of allFields(config)) {
    if (field.type !== "actionTracker") {
      columns.push({ code: field.code, field, derived: null });
      continue;
    }
    for (const action of field.actions) {
      const base = `${field.code}_${action.code}`;
      columns.push({ code: `${base}_count`, field, derived: "count" });
      columns.push({ code: `${base}_times`, field, derived: "times" });
    }
  }
  return columns;
}

const isMap = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const text = (v: unknown) => (v === null || v === undefined ? "" : String(v));

function cellText(column: PayloadColumn, value: unknown): string {
  if (column.derived === "count") return value == null ? "0" : String(value);
  if (column.derived === "times") return text(value);
  if (value === null || value === undefined) return "";
  if (isMap(value)) return text(value.teamNumber);
  if (Array.isArray(value)) return selectedKeys(value).join(",");
  return String(value);
}

export function encodeQrScout(config: ScoutConfig, values: Values): string {
  const { delimiter } = config;
  return payloadColumns(config)
    .map((c) =>
      cellText(c, values[c.code])
        .split(delimiter)
        .join(" ")
        .replace(/[\r\n]/g, " "),
    )
    .join(delimiter);
}

export interface DecodedPayload {
  values: Values;
  doubles: Set<string>;
}

type Parsed = { n: number; double: boolean } | null;

function parseNum(raw: string): Parsed {
  const s = raw.trim();
  if (/^[+-]?\d+$/.test(s)) return { n: Number(s), double: false };
  if (/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s)) {
    return { n: Number(s), double: true };
  }
  return null;
}

function parseCell(
  column: PayloadColumn,
  raw: string,
  out: DecodedPayload,
): void {
  const { code, field } = column;
  if (column.derived === "count") {
    const s = raw.trim();
    out.values[code] = /^[+-]?\d+$/.test(s) ? Number(s) : 0;
    return;
  }
  if (column.derived === "times") {
    out.values[code] = raw;
    return;
  }
  const number = (asDouble: boolean) => {
    const parsed = parseNum(raw);
    if (parsed === null) {
      out.values[code] = effectiveDefault(field);
      return;
    }
    out.values[code] = parsed.n;
    if (asDouble || parsed.double) out.doubles.add(code);
  };
  switch (field.type) {
    case "number":
    case "counter":
    case "multiCounter":
    case "tbaMatchNumber":
      number(false);
      break;
    case "range":
      number(true);
      break;
    case "tbaTeamAndRobot": {
      const team = /^[+-]?\d+$/.test(raw.trim()) ? Number(raw.trim()) : null;
      out.values[code] =
        team === null ? null : { teamNumber: team, robotPosition: "" };
      break;
    }
    case "boolean":
      out.values[code] = raw.toLowerCase() === "true";
      break;
    default:
      out.values[code] = raw;
  }
}

export function decodeQrScout(
  config: ScoutConfig,
  payload: string,
): DecodedPayload | null {
  const columns = payloadColumns(config);
  if (columns.length === 0) return null;
  const parts = payload.split(config.delimiter);
  if (Math.abs(parts.length - columns.length) > 2) return null;
  const out: DecodedPayload = { values: {}, doubles: new Set() };
  columns.forEach((column, i) => {
    const raw = parts[i];
    if (raw !== undefined) parseCell(column, raw, out);
    else if (column.derived !== null) parseCell(column, "", out);
  });
  return out;
}
