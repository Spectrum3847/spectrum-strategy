import { maxCorrectedText } from "../data/corrections";
import { stationOfEntry } from "../export/csv";
import {
  choiceOptions,
  resolveStoredChoice,
  type ScoutField,
  selectedKeys,
} from "../scout/config";
import { teamCodes } from "../scout/entry";
import { isNameField } from "../team/format";

export type CellKind =
  | "text"
  | "longText"
  | "number"
  | "counter"
  | "range"
  | "boolean"
  | "select"
  | "multi";

export type Parsed =
  | { ok: true; value: unknown }
  | { ok: false; reason: string };

export function cellKind(field: ScoutField): CellKind {
  switch (field.type) {
    case "checkboxSelect":
      return "multi";
    case "multiCounter":
      return "counter";
    case "text":
    case "longText":
    case "number":
    case "counter":
    case "range":
    case "boolean":
    case "select":
      return field.type;
    default:
      return "text";
  }
}

export function isReadOnly(field: ScoutField): boolean {
  return (
    teamCodes.includes(field.code) ||
    isNameField(field) ||
    (field.choices ?? []).some(([key]) => stationOfEntry({ key }) !== "")
  );
}

export const isOn = (value: unknown) => value === true || value === "true";

export function editText(field: ScoutField, value: unknown): string {
  const kind = cellKind(field);
  if (kind === "select") return resolveStoredChoice(field, value) ?? "";
  if (kind === "multi" || kind === "boolean") return "";
  return value === undefined || value === null ? "" : String(value);
}

function bounds(field: ScoutField, kind: CellKind): [number, number | null] {
  if (kind === "range") return [field.min ?? 0, field.max ?? 100];
  return [Math.max(0, field.min ?? 0), field.max];
}

function numeric(field: ScoutField, kind: CellKind, text: string): Parsed {
  const t = text.trim();
  if (!/^-?\d+(\.\d+)?$/.test(t)) {
    return { ok: false, reason: "Enter a number." };
  }
  const n = Number(t);
  if (kind === "counter" && !Number.isInteger(n)) {
    return { ok: false, reason: "Enter a whole number." };
  }
  const [min, max] = bounds(field, kind);
  if (n < min) return { ok: false, reason: `The lowest value is ${min}.` };
  if (max !== null && n > max) {
    return { ok: false, reason: `The highest value is ${max}.` };
  }
  return { ok: true, value: kind === "number" ? t : n };
}

export function parseCell(field: ScoutField, text: string): Parsed {
  const kind = cellKind(field);
  switch (kind) {
    case "text":
    case "longText":
      return text.length > maxCorrectedText
        ? { ok: false, reason: `Keep it under ${maxCorrectedText} characters.` }
        : { ok: true, value: text };
    case "number":
      return text.trim() === ""
        ? { ok: true, value: "" }
        : numeric(field, kind, text);
    case "counter":
    case "range":
      return numeric(field, kind, text);
    case "boolean":
      return { ok: true, value: isOn(text) };
    case "select": {
      if (text === "") return { ok: true, value: "" };
      const valid = choiceOptions(field, [text]).some(([k]) => k === text);
      return valid
        ? { ok: true, value: text }
        : { ok: false, reason: "Pick one of the choices." };
    }
    case "multi": {
      const keys = selectedKeys(text);
      const valid = new Set(choiceOptions(field, keys).map(([k]) => k));
      return keys.every((k) => valid.has(k))
        ? { ok: true, value: keys.join(",") }
        : { ok: false, reason: "Pick from the choices." };
    }
  }
}

export function blankCell(field: ScoutField): Parsed {
  const kind = cellKind(field);
  return kind === "counter" || kind === "range" || kind === "boolean"
    ? { ok: false, reason: "This answer cannot be blank." }
    : { ok: true, value: "" };
}
