import { Timestamp } from "firebase/firestore";
import type { Values } from "../scout/config";

export const maxCorrectedFields = 100;
export const maxCorrectionNote = 500;
export const maxCorrectedText = 4096;
export const maxHistory = 200;
export const maxHistoryText = 200;

export type HistoryHow = "table" | "form" | "undo";
type Scalar = string | number | boolean;

export interface HistoryEntry {
  at: number;
  by: string;
  uid: string;
  how: HistoryHow;
  field: string;
  from: Scalar;
  to: Scalar;
}

export interface Correction {
  id: string;
  eventKey: string;
  fields: Values;
  note: string;
  authorUid: string;
  authorDisplayName: string;
  history: HistoryEntry[];
  updatedMs: number;
}

export interface CorrectionAuthor {
  uid: string;
  displayName: string;
}

type Raw = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" ? v : "");
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const scalar = (v: unknown): v is string | number | boolean =>
  typeof v === "string" ||
  typeof v === "boolean" ||
  (typeof v === "number" && Number.isFinite(v));

const hows: readonly string[] = ["table", "form", "undo"];

function parseHistory(raw: unknown): HistoryEntry[] {
  if (!Array.isArray(raw)) return [];
  const out: HistoryEntry[] = [];
  for (const item of raw) {
    if (!isRecord(item)) continue;
    const { at, how, field, from, to } = item;
    if (typeof at !== "number" || !Number.isFinite(at)) continue;
    if (typeof how !== "string" || !hows.includes(how)) continue;
    if (typeof field !== "string" || !scalar(from) || !scalar(to)) continue;
    out.push({
      at,
      by: str(item.by),
      uid: str(item.uid),
      how: how as HistoryHow,
      field,
      from,
      to,
    });
  }
  return out;
}

export function parseCorrection(id: string, data: Raw): Correction {
  const fields: Values = {};
  if (isRecord(data.fields)) {
    for (const [code, value] of Object.entries(data.fields)) {
      if (scalar(value)) fields[code] = value;
    }
  }
  const parsed = Date.parse(str(data.updatedAt));
  return {
    id,
    eventKey: str(data.eventKey),
    fields,
    note: str(data.note),
    authorUid: str(data.authorUid),
    authorDisplayName: str(data.authorDisplayName),
    history: parseHistory(data.history),
    updatedMs:
      data.updatedAtTs instanceof Timestamp
        ? data.updatedAtTs.toMillis()
        : Number.isNaN(parsed)
          ? 0
          : parsed,
  };
}

export function nextCorrection(
  prev: Correction | null,
  entryId: string,
  eventKey: string,
  fields: Values,
  note: string,
  author: CorrectionAuthor,
  nowMs: number,
  history: HistoryEntry[] = prev?.history ?? [],
): Correction {
  const kept: Values = {};
  for (const [code, value] of Object.entries(fields)) {
    kept[code] =
      typeof value === "string" ? value.slice(0, maxCorrectedText) : value;
  }
  return {
    id: entryId,
    eventKey,
    fields: kept,
    note: note.trim().slice(0, maxCorrectionNote),
    authorUid: author.uid,
    authorDisplayName: author.displayName.slice(0, 128),
    history: history.slice(-maxHistory),
    updatedMs: Math.max(nowMs, prev?.updatedMs ?? 0),
  };
}

export function correctionDoc(c: Correction): Raw {
  return {
    entryId: c.id,
    eventKey: c.eventKey,
    fields: c.fields,
    note: c.note,
    authorUid: c.authorUid,
    authorDisplayName: c.authorDisplayName,
    history: c.history,
    updatedAt: new Date(c.updatedMs).toISOString(),
    updatedAtTs: Timestamp.fromMillis(c.updatedMs),
  };
}
