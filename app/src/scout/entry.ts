import { Timestamp } from "firebase/firestore";
import {
  allFields,
  allianceFromStation,
  type ScoutConfig,
  storedCounter,
  type Values,
} from "./config";

export const teamCodes = ["pTnumber", "teamNumber", "team", "teamNum"];

const phases = ["auton", "teleop", "endgame"] as const;

const textTypes = new Set(["text", "longText", "number", "tbaMatchNumber"]);

export function extractTeam(config: ScoutConfig, values: Values): number {
  const asTeam = (v: unknown) => {
    const n =
      typeof v === "number" ? Math.trunc(v) : Number.parseInt(String(v), 10);
    return Number.isInteger(n) && n > 0 ? n : null;
  };
  for (const field of allFields(config)) {
    if (field.type !== "tbaTeamAndRobot") continue;
    const value = values[field.code];
    if (typeof value === "object" && value !== null) {
      const team = asTeam((value as Record<string, unknown>).teamNumber);
      if (team !== null) return team;
    }
  }
  for (const code of teamCodes) {
    const v = values[code];
    if (v === undefined || v === null) continue;
    const team = asTeam(v);
    if (team !== null) return team;
  }
  return 0;
}

export function fieldValuesFor(config: ScoutConfig, values: Values): Values {
  const out: Values = { ...values };
  for (const field of allFields(config)) {
    const v = out[field.code];
    if (textTypes.has(field.type)) {
      out[field.code] = v === undefined || v === null ? "" : String(v);
    } else if (field.type === "counter" || field.type === "multiCounter") {
      const n = storedCounter(v);
      if (n !== null) out[field.code] = n;
    }
  }
  for (const key of Object.keys(out))
    if (out[key] === undefined) delete out[key];
  return out;
}

export function allianceOf(values: Values): "Red" | "Blue" {
  const found = new Set<"Red" | "Blue">();
  for (const v of Object.values(values)) {
    const a = allianceFromStation(v);
    if (a) found.add(a);
  }
  return found.size === 1 ? ([...found][0] ?? "Red") : "Red";
}

export function matchIdFor(
  tbaMatchKey: string | null,
  eventKey: string,
  typedMatch: string,
): string {
  if (tbaMatchKey) return tbaMatchKey;
  return `${eventKey || "unscheduled"}_typed_${typedMatch.trim()}`.slice(
    0,
    128,
  );
}

export interface EntryInput {
  id: string;
  config: ScoutConfig;
  values: Values;
  matchId: string;
  tbaMatchKey: string | null;
  authorUid: string;
  authorDisplayName: string;
  scoutedBy?: { name: string; uid: string };
  now: Date;
  createdAt?: string;
  rawValues?: boolean;
  strokesByPhase?: Record<string, unknown[]> | null;
}

export function entryDocument(input: EntryInput): Record<string, unknown> {
  const fieldValues = input.rawValues
    ? { ...input.values }
    : fieldValuesFor(input.config, input.values);
  const updatedAt = input.now.toISOString();
  const doc: Record<string, unknown> = {
    id: input.id,
    matchId: input.matchId,
    teamNumber: extractTeam(input.config, input.values),
    alliance: allianceOf(input.values),
    notes: "",
    authorUid: input.authorUid,
    authorDisplayName: input.authorDisplayName.slice(0, 128),
    updatedAt,
    createdAt: input.createdAt ?? updatedAt,
    byPhase: Object.fromEntries(
      phases.map((p) => [
        p,
        { score: 0, penalties: 0, notes: "", counters: {} },
      ]),
    ),
  };
  const credited = input.scoutedBy?.name.trim().slice(0, 128);
  if (credited) {
    doc.scoutedByName = credited;
    const uid = input.scoutedBy?.uid.slice(0, 128);
    if (uid) doc.scoutedByUid = uid;
  }
  if (Object.keys(fieldValues).length > 0) doc.fieldValues = fieldValues;
  if (input.tbaMatchKey !== null) doc.tbaMatchKey = input.tbaMatchKey;
  if (input.strokesByPhase) doc.strokesByPhase = input.strokesByPhase;
  doc.updatedAtTs = Timestamp.fromDate(input.now);
  return doc;
}
