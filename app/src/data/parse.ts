import { Timestamp } from "firebase/firestore";
import type { Values } from "../scout/config";
import type { RemoteEntry } from "../scout/schedule";

type Raw = Record<string, unknown>;

const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : "");
const int = (v: unknown) => {
  const n = typeof v === "number" ? v : Number.parseInt(String(v ?? ""), 10);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
};
const values = (v: unknown): Values => (isRecord(v) ? v : {});

export interface EventEntry extends RemoteEntry {
  teamNumber: number;
  alliance: string;
  scoutName: string;
  createdAt?: string;
  scoutedByName?: string;
  authorDisplayName?: string;
  scouterUid?: string;
  authorUid?: string;
  addedManually?: boolean;
  strokesByPhase?: Record<string, unknown>;
  updatedAt: string;
}

export function parseEventEntry(id: string, data: Raw): EventEntry {
  return {
    id,
    tbaMatchKey:
      typeof data.tbaMatchKey === "string" && data.tbaMatchKey !== ""
        ? data.tbaMatchKey
        : null,
    fieldValues: values(data.fieldValues),
    teamNumber: int(data.teamNumber),
    alliance: str(data.alliance),
    scoutName:
      str(data.scoutedByName).trim() || str(data.authorDisplayName).trim(),
    ...(str(data.createdAt) !== "" && { createdAt: str(data.createdAt) }),
    scoutedByName: str(data.scoutedByName),
    authorDisplayName: str(data.authorDisplayName),
    scouterUid:
      str(data.scoutedByName) !== ""
        ? str(data.scoutedByUid)
        : str(data.authorUid),
    authorUid: str(data.authorUid),
    ...(data.addedManually === true && { addedManually: true }),
    ...(isRecord(data.strokesByPhase) &&
      Object.keys(data.strokesByPhase).length > 0 && {
        strokesByPhase: data.strokesByPhase,
      }),
    updatedAt: str(data.updatedAt),
  };
}

export interface FormEntry {
  id: string;
  teamNumber: number;
  eventKey: string;
  fieldValues: Values;
  authorUid: string;
  scoutName: string;
  updatedAt: string;
  stampMs?: number;
}

export interface PitEntry extends FormEntry {
  photoKeys: string[];
}

export type PrescoutEntry = FormEntry;

function parseFormEntry(id: string, data: Raw): FormEntry {
  return {
    id,
    teamNumber: int(data.teamNumber),
    eventKey: str(data.eventKey),
    fieldValues: values(data.fieldValues),
    authorUid: str(data.authorUid),
    scoutName: str(data.authorDisplayName).trim(),
    updatedAt: str(data.updatedAt),
    ...(data.updatedAtTs instanceof Timestamp && {
      stampMs: data.updatedAtTs.toMillis(),
    }),
  };
}

export function parsePitEntry(id: string, data: Raw): PitEntry {
  return {
    ...parseFormEntry(id, data),
    photoKeys: Array.isArray(data.photoKeys)
      ? data.photoKeys.filter((k): k is string => typeof k === "string")
      : [],
  };
}

export const parsePrescoutEntry = parseFormEntry;

export interface TrexReport {
  id: string;
  trait: string;
  teamNumber: number;
  matchNumber: number;
  eventName: string;
  eventKey: string;
  report: string;
  rating: number | null;
  strokes?: unknown[];
  scoutName: string;
  authorUid?: string;
  updatedAt: string;
}

const rating = (v: unknown) =>
  typeof v === "number" && Number.isInteger(v) && v >= 1 && v <= 5 ? v : null;

export function parseTrexReport(id: string, data: Raw): TrexReport {
  return {
    id,
    trait: str(data.trait),
    teamNumber: int(data.teamNumber),
    matchNumber: int(data.matchNumber),
    eventName: str(data.eventName).trim(),
    eventKey: str(data.eventKey),
    report: str(data.report),
    rating: rating(data.rating),
    ...(Array.isArray(data.strokes) &&
      data.strokes.length > 0 && { strokes: data.strokes }),
    scoutName: str(data.authorDisplayName).trim(),
    authorUid: str(data.authorUid),
    updatedAt: str(data.updatedAt),
  };
}
