export type FieldType =
  | "text"
  | "longText"
  | "number"
  | "boolean"
  | "select"
  | "range"
  | "counter"
  | "multiCounter"
  | "actionTracker"
  | "tbaMatchNumber"
  | "tbaTeamAndRobot"
  | "checkboxSelect"
  | "document";

export type ResetBehavior = "reset" | "preserve" | "increment";

export interface TrackedAction {
  code: string;
  label: string;
}

export interface ScoutField {
  title: string;
  description: string;
  type: FieldType;
  rawType: string;
  required: boolean;
  code: string;
  resetBehavior: ResetBehavior;
  defaultValue: unknown;
  choices: [string, string][] | null;
  retired: ReadonlySet<string>;
  min: number | null;
  max: number | null;
  step: number | null;
  buttons: number[] | null;
  actions: TrackedAction[];
  trackerMode: "tap" | "hold";
  visibleWhenCode: string;
  visibleWhenValue: string;
}

export interface ScoutSection {
  name: string;
  fields: ScoutField[];
}

export interface ScoutConfig {
  title: string;
  revision: number;
  delimiter: string;
  reportDrawing?: boolean;
  sections: ScoutSection[];
}

export type Values = Record<string, unknown>;

const normalizeType = (s: string) => s.toLowerCase().replace(/[-_]/g, "");

const typeNames: Record<string, FieldType> = {
  text: "text",
  longtext: "longText",
  number: "number",
  boolean: "boolean",
  checkbox: "boolean",
  select: "select",
  dropdown: "select",
  range: "range",
  slider: "range",
  counter: "counter",
  multicounter: "multiCounter",
  actiontracker: "actionTracker",
  tbamatchnumber: "tbaMatchNumber",
  tbateamandrobot: "tbaTeamAndRobot",
  checkboxselect: "checkboxSelect",
  multiselect: "checkboxSelect",
  document: "document",
  file: "document",
};

export function fieldTypeOf(raw: string): FieldType {
  return typeNames[normalizeType(raw)] ?? "text";
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown, fallback = "") =>
  typeof v === "string" ? v : fallback;
const num = (v: unknown) => (typeof v === "number" ? v : null);

function parseChoices(raw: unknown): [string, string][] | null {
  if (isRecord(raw)) return Object.entries(raw).map(([k, v]) => [k, String(v)]);
  if (Array.isArray(raw)) return raw.map((v) => [String(v), String(v)]);
  return null;
}

function parseField(raw: Raw): ScoutField {
  const rawType = str(raw.type, "text");
  const reset = str(raw.formResetBehavior, "reset");
  const buttons = Array.isArray(raw.buttons)
    ? raw.buttons.filter((n): n is number => typeof n === "number")
    : [];
  return {
    title: str(raw.title),
    description: str(raw.description),
    type: fieldTypeOf(rawType),
    rawType,
    required: raw.required === true,
    code: str(raw.code),
    resetBehavior:
      reset === "preserve" || reset === "increment" ? reset : "reset",
    defaultValue: raw.defaultValue ?? null,
    choices: parseChoices(raw.choices),
    retired: new Set(
      Array.isArray(raw.retiredChoiceKeys)
        ? raw.retiredChoiceKeys.map(String)
        : [],
    ),
    min: num(raw.min),
    max: num(raw.max),
    step: num(raw.step),
    buttons: buttons.length > 0 ? buttons.map(Math.trunc) : null,
    actions: Array.isArray(raw.actions)
      ? raw.actions.filter(isRecord).map((a) => ({
          code: str(a.code),
          label: str(a.label).trim() || str(a.code),
        }))
      : [],
    trackerMode: raw.mode === "tap" ? "tap" : "hold",
    visibleWhenCode: str(raw.visibleWhenCode),
    visibleWhenValue: str(raw.visibleWhenValue),
  };
}

function delimiterOf(raw: unknown): string {
  return typeof raw === "string" && raw.length >= 1 && raw.length <= 4
    ? raw
    : "\t";
}

export function parseConfig(input: unknown): ScoutConfig {
  const json: unknown = typeof input === "string" ? JSON.parse(input) : input;
  if (!isRecord(json)) throw new Error("Scout config is not an object");
  const sections = Array.isArray(json.sections) ? json.sections : [];
  return {
    title: str(json.title, "Scout"),
    revision: Math.trunc(num(json.revision) ?? 0),
    delimiter: delimiterOf(json.delimiter),
    reportDrawing: json.report_drawing !== false,
    sections: sections.filter(isRecord).map((s) => ({
      name: str(s.name),
      fields: (Array.isArray(s.fields) ? s.fields : [])
        .filter(isRecord)
        .map(parseField),
    })),
  };
}

export function pickConfig(active: ScoutConfig, incoming: ScoutConfig) {
  return incoming.revision > active.revision ? incoming : active;
}

export const allFields = (config: ScoutConfig) =>
  config.sections.flatMap((s) => s.fields);

export function selectedKeys(value: unknown): string[] {
  const parts = Array.isArray(value)
    ? value.map(String)
    : typeof value === "string"
      ? value.split(",")
      : [];
  return parts.map((p) => p.trim()).filter((p) => p !== "");
}

export const activeChoices = (field: ScoutField): [string, string][] =>
  (field.choices ?? []).filter(([key]) => !field.retired.has(key));

export function choiceOptions(
  field: ScoutField,
  keep: Iterable<string>,
): [string, string][] {
  const kept = new Set(keep);
  return (field.choices ?? []).filter(
    ([key]) => !field.retired.has(key) || kept.has(key),
  );
}

export function effectiveDefault(field: ScoutField): unknown {
  if (field.type === "checkboxSelect") {
    return selectedKeys(field.defaultValue).join(",");
  }
  if (field.defaultValue !== null) {
    if (field.type === "select" && typeof field.defaultValue === "string") {
      const choices = field.choices ?? [];
      if (!choices.some(([key]) => key === field.defaultValue)) {
        const byLabel = choices.find(
          ([, label]) => label === field.defaultValue,
        );
        if (byLabel) return byLabel[0];
      }
    }
    return field.defaultValue;
  }
  switch (field.type) {
    case "text":
    case "longText":
    case "document":
      return "";
    case "number":
    case "counter":
    case "range":
    case "multiCounter":
    case "tbaMatchNumber":
      return 0;
    case "boolean":
      return false;
    case "select":
      return activeChoices(field)[0]?.[0] ?? field.choices?.[0]?.[0] ?? "";
    case "actionTracker":
    case "tbaTeamAndRobot":
      return null;
  }
}

export function isVisible(field: ScoutField, values: Values): boolean {
  if (field.visibleWhenCode === "") return true;
  const held = values[field.visibleWhenCode];
  return (
    (held === undefined || held === null ? "" : String(held)) ===
    field.visibleWhenValue
  );
}

export function resolveStoredChoice(
  field: ScoutField,
  stored: unknown,
): string | null {
  const value = stored === undefined || stored === null ? "" : String(stored);
  if (value === "" || !field.choices) return null;
  if (field.choices.some(([k]) => k === value)) return value;
  return field.choices.find(([, label]) => label === value)?.[0] ?? null;
}

export function labelForStored(field: ScoutField, stored: unknown): string {
  const value = stored === undefined || stored === null ? "" : String(stored);
  const key = resolveStoredChoice(field, value);
  if (key === null) return value;
  return field.choices?.find(([k]) => k === key)?.[1] ?? value;
}

export function storedCounter(value: unknown): number | null {
  const n =
    typeof value === "number"
      ? value
      : Number.parseFloat(String(value ?? "").trim());
  return Number.isFinite(n) ? Math.round(n) : null;
}

const flatten = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");

function isEmpty(field: ScoutField, value: unknown): boolean {
  switch (field.type) {
    case "boolean":
    case "counter":
    case "multiCounter":
    case "range":
    case "actionTracker":
      return false;
    case "tbaTeamAndRobot": {
      if (typeof value !== "object" || value === null) return true;
      const team = Number((value as Raw).teamNumber);
      return !(team > 0);
    }
    case "number": {
      const text = String(value ?? "").trim();
      const n = text === "" ? Number.NaN : Number(text);
      if (Number.isNaN(n)) return true;
      return (
        (field.min !== null && n < field.min) ||
        (field.max !== null && n > field.max)
      );
    }
    default:
      return String(value ?? "").trim() === "";
  }
}

export function emptyRequiredFields(
  config: ScoutConfig,
  values: Values,
): ScoutField[] {
  const fields = allFields(config);
  const noShow = fields.some(
    (f) =>
      f.type === "select" && flatten(String(values[f.code] ?? "")) === "noshow",
  );
  if (noShow) return [];
  return fields.filter(
    (f) => f.required && isVisible(f, values) && isEmpty(f, values[f.code]),
  );
}

export function normalizeStation(station: string): string | null {
  const m = /^(RED|BLUE|R|B)\s*([123])$/.exec(station.trim().toUpperCase());
  if (!m) return null;
  return `${m[1]?.startsWith("R") ? "R" : "B"}${m[2]}`;
}

export function allianceFromStation(value: unknown): "Red" | "Blue" | null {
  if (typeof value !== "string") return null;
  const s = value.trim().toUpperCase();
  if (s.length !== 2 || !"123".includes(s[1] ?? "x")) return null;
  if (s[0] === "R") return "Red";
  if (s[0] === "B") return "Blue";
  return null;
}
