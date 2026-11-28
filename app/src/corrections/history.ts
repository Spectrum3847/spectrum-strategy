import {
  type Correction,
  type CorrectionAuthor,
  type HistoryEntry,
  type HistoryHow,
  maxHistory,
  maxHistoryText,
} from "../data/corrections";
import type { Values } from "../scout/config";
import { sameValue } from "./apply";

export interface Change {
  field: string;
  from: HistoryEntry["from"];
  to: HistoryEntry["to"];
}

export function historyValue(v: unknown): HistoryEntry["to"] {
  if (v === undefined || v === null) return "";
  if (typeof v === "boolean") return v;
  if (typeof v === "number" && Number.isFinite(v)) return v;
  return String(v).slice(0, maxHistoryText);
}

export function diffFields(
  before: Values,
  after: Values,
  codes: Iterable<string>,
): Change[] {
  const out: Change[] = [];
  for (const field of new Set(codes)) {
    if (sameValue(before[field], after[field])) continue;
    out.push({
      field,
      from: historyValue(before[field]),
      to: historyValue(after[field]),
    });
  }
  return out;
}

export function stamp(
  changes: Change[],
  how: HistoryHow,
  author: CorrectionAuthor,
  nowMs: number,
): HistoryEntry[] {
  return changes.map((c) => ({
    ...c,
    at: nowMs,
    by: author.displayName.slice(0, 128),
    uid: author.uid,
    how,
  }));
}

export const appendHistory = (prev: HistoryEntry[], added: HistoryEntry[]) =>
  [...prev, ...added].slice(-maxHistory);

export interface EditInfo {
  by: string;
  atMs: number;
  how: HistoryHow;
}

export function editInfo(
  correction: Correction | null,
  code: string,
): EditInfo | null {
  if (!correction) return null;
  for (let i = correction.history.length - 1; i >= 0; i--) {
    const h = correction.history[i];
    if (h && h.field === code) return { by: h.by, atMs: h.at, how: h.how };
  }
  return code in correction.fields
    ? {
        by: correction.authorDisplayName,
        atMs: correction.updatedMs,
        how: "form",
      }
    : null;
}

export function historyList(
  correction: Correction | null,
  corrected: string[],
  raw: Values,
  values: Values,
): HistoryEntry[] {
  if (!correction) return [];
  const listed = new Set(correction.history.map((h) => h.field));
  const legacy: HistoryEntry[] = corrected
    .filter((code) => !listed.has(code))
    .map((field) => ({
      at: correction.updatedMs,
      by: correction.authorDisplayName,
      uid: correction.authorUid,
      how: "form",
      field,
      from: historyValue(raw[field]),
      to: historyValue(values[field]),
    }));
  return [...legacy, ...correction.history].reverse();
}
