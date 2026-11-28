import { fieldTypeOf } from "../scout/config";
import {
  type Doc,
  delimiterOf,
  fieldsOf,
  isRecord,
  normalizeTypeName,
  sectionFields,
  sectionsOf,
  textOf,
} from "./doc";

export type Check =
  | { ok: true; doc: Doc; warnings: string[] }
  | { ok: false; error: string };

type Kind = "string" | "number" | "boolean" | "array";

const kindWords: Record<Kind, string> = {
  string: "text",
  number: "a number",
  boolean: "true or false",
  array: "a list",
};

const topKinds: Record<string, Kind> = {
  title: "string",
  page_title: "string",
  delimiter: "string",
  revision: "number",
  report_drawing: "boolean",
  sections: "array",
};
const sectionKinds: Record<string, Kind> = { name: "string", fields: "array" };
const fieldKinds: Record<string, Kind> = {
  title: "string",
  description: "string",
  type: "string",
  code: "string",
  formResetBehavior: "string",
  referenceImageAsset: "string",
  visibleWhenCode: "string",
  visibleWhenValue: "string",
  mode: "string",
  required: "boolean",
  min: "number",
  max: "number",
  step: "number",
  timerDuration: "number",
  autoStopSeconds: "number",
  buttons: "array",
  retiredChoiceKeys: "array",
  actions: "array",
};
const actionKinds: Record<string, Kind> = {
  code: "string",
  label: "string",
  icon: "string",
};

function kindOf(value: unknown): Kind | "other" {
  if (typeof value === "string") return "string";
  if (typeof value === "number") return "number";
  if (typeof value === "boolean") return "boolean";
  if (Array.isArray(value)) return "array";
  return "other";
}

function wrongKind(obj: Doc, kinds: Record<string, Kind>): string | null {
  for (const [key, kind] of Object.entries(kinds)) {
    const value = obj[key];
    if (value === undefined || value === null) continue;
    if (kindOf(value) !== kind) return `"${key}" must be ${kindWords[kind]}.`;
  }
  return null;
}

export function typeProblem(doc: Doc): string | null {
  const top = wrongKind(doc, topKinds);
  if (top) return `Config: ${top}`;
  for (const [si, section] of sectionsOf(doc).entries()) {
    const where = `Section ${textOf(section.name) || `#${si + 1}`}`;
    const bad = wrongKind(section, sectionKinds);
    if (bad) return `${where}: ${bad}`;
    for (const [fi, field] of sectionFields(section).entries()) {
      const name = `${where}, field ${textOf(field.code) || `#${fi + 1}`}`;
      const wrong = wrongKind(field, fieldKinds);
      if (wrong) return `${name}: ${wrong}`;
      for (const action of Array.isArray(field.actions) ? field.actions : []) {
        if (!isRecord(action)) continue;
        const bad = wrongKind(action, actionKinds);
        if (bad) return `${name}, action: ${bad}`;
      }
    }
  }
  return null;
}

const rawTypeOf = (field: Doc) => textOf(field.type, "text");

function choiceValues(field: Doc): string[] | null {
  const raw = field.choices;
  if (isRecord(raw)) return Object.values(raw).map(String);
  if (Array.isArray(raw)) return raw.map(String);
  return null;
}

export const duplicateOptionMessage = (code: string) =>
  `Select field "${code}" has duplicate option values; each option must map to a unique value.`;

export function validationError(doc: Doc): string | null {
  const fields = fieldsOf(doc);
  for (const field of fields) {
    if (fieldTypeOf(rawTypeOf(field)) !== "select") continue;
    const values = choiceValues(field);
    if (values && new Set(values).size !== values.length) {
      return duplicateOptionMessage(textOf(field.code));
    }
  }
  const trackers = fields.filter(
    (f) => fieldTypeOf(rawTypeOf(f)) === "actionTracker",
  );
  if (trackers.length === 0) return null;
  const delimiter = delimiterOf(doc.delimiter);
  if (delimiter === ",") {
    return (
      'This config uses "," as its delimiter and has an action tracker, ' +
      "which joins its timestamps with commas. One would destroy the other, " +
      "so use a tab delimiter or drop the tracker."
    );
  }
  if (delimiter === "-" && trackers.some((f) => f.mode !== "tap")) {
    return (
      'This config uses "-" as its delimiter and has a hold-mode action ' +
      "tracker, which writes each span as start-end. One would destroy the " +
      "other, so use a tab delimiter or switch the tracker to tap mode."
    );
  }
  return null;
}

const knownUnsupported: Record<string, string> = {
  timer: "the cycle logger covers timing instead",
  image: "photos are pit-only for now",
};

export function unsupportedTypes(doc: Doc): {
  known: string[];
  unrecognised: string[];
} {
  const seen = new Set<string>();
  const known: string[] = [];
  const unrecognised: string[] = [];
  for (const field of fieldsOf(doc)) {
    const raw = textOf(field.type);
    const name = normalizeTypeName(raw);
    if (raw === "" || name === "text" || fieldTypeOf(raw) !== "text") continue;
    if (seen.has(name)) continue;
    seen.add(name);
    (name in knownUnsupported ? known : unrecognised).push(raw);
  }
  return { known, unrecognised };
}

function unsupportedWarning(doc: Doc): string | null {
  const { known, unrecognised } = unsupportedTypes(doc);
  if (known.length === 0 && unrecognised.length === 0) return null;
  const parts: string[] = [];
  if (known.length > 0) {
    const lines = known
      .map((t) => `${t} (${knownUnsupported[normalizeTypeName(t)]})`)
      .join(", ");
    parts.push(
      `This app does not render these field types yet, so they become text boxes: ${lines}.`,
    );
  }
  if (unrecognised.length > 0) {
    parts.push(
      `These field types are not recognised at all, which usually means QRScout added them after this app last looked: ${unrecognised.join(", ")}.`,
    );
  }
  parts.push(
    "Scouters will type into those fields instead of picking, and the values arrive as free text.",
  );
  return parts.join(" ");
}

function codeWarnings(doc: Doc): string[] {
  const seen = new Set<string>();
  const repeated = new Set<string>();
  let empty = 0;
  for (const field of fieldsOf(doc)) {
    const code = textOf(field.code);
    if (code === "") empty += 1;
    else if (seen.has(code)) repeated.add(code);
    else seen.add(code);
  }
  const out: string[] = [];
  if (repeated.size > 0) {
    out.push(
      `Field code ${[...repeated].map((c) => `"${c}"`).join(", ")} is used more than once. Those fields share one answer.`,
    );
  }
  if (empty > 0) {
    out.push(
      `${empty} ${empty === 1 ? "field has" : "fields have"} no code, so ${empty === 1 ? "its" : "their"} answers cannot be stored.`,
    );
  }
  return out;
}

export function checkConfigDoc(value: unknown): Check {
  if (!isRecord(value)) {
    return { ok: false, error: "Config JSON must be an object." };
  }
  const problem = typeProblem(value);
  if (problem) return { ok: false, error: problem };
  if (sectionsOf(value).length === 0) {
    return { ok: false, error: "Config has no sections." };
  }
  const invalid = validationError(value);
  if (invalid) return { ok: false, error: invalid };
  const warnings = [unsupportedWarning(value), ...codeWarnings(value)].filter(
    (w): w is string => w !== null,
  );
  return { ok: true, doc: value, warnings };
}

export function checkConfigText(text: string): Check {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch (error) {
    const reason = error instanceof Error ? error.message : "unreadable";
    return { ok: false, error: `This is not valid JSON: ${reason}` };
  }
  return checkConfigDoc(value);
}
