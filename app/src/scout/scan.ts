import type { ScoutConfig, Values } from "./config";
import { entryDocument, matchIdFor } from "./entry";
import { matchCode } from "./formState";
import { matchRefOf, type SavedEntry } from "./local";
import { decodeQrScout, encodeQrScout } from "./qr";
import {
  type RemoteEntry,
  resolveMatchKey,
  type ScheduledMatch,
  stationOf,
} from "./schedule";

function dartJson(value: unknown, isDouble = false): string {
  if (typeof value === "number") {
    return isDouble && Number.isInteger(value) ? `${value}.0` : String(value);
  }
  if (Array.isArray(value))
    return `[${value.map((v) => dartJson(v)).join(",")}]`;
  if (typeof value === "object" && value !== null) {
    return `{${Object.entries(value)
      .map(([k, v]) => `${JSON.stringify(k)}:${dartJson(v)}`)
      .join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

const emptyPhase = '{"score":0,"penalties":0,"notes":"","counters":{}}';

export function contentSignature(
  tbaMatchKey: string | null,
  teamNumber: number,
  values: Values,
  doubles: ReadonlySet<string>,
): string {
  const fields = Object.entries(values)
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${JSON.stringify(k)}:${dartJson(v, doubles.has(k))}`)
    .join(",");
  return (
    `{"matchId":"","tbaMatchKey":${JSON.stringify(tbaMatchKey ?? "")},` +
    `"teamNumber":${teamNumber},"alliance":"Red","notes":"",` +
    `"fieldValues":{${fields}},"byPhase":{"auton":${emptyPhase},` +
    `"teleop":${emptyPhase},"endgame":${emptyPhase}}}`
  );
}

export function stableHash(input: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash = Math.imul(hash ^ input.charCodeAt(i), 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export const scanIdFor = (signature: string) => `scan-${stableHash(signature)}`;

function scanTeam(values: Values): number {
  for (const code of ["pTnumber", "team", "teamNumber"]) {
    const v = values[code];
    if (typeof v === "number") return Math.trunc(v);
  }
  return 0;
}

export interface ScanContext {
  config: ScoutConfig;
  schedule: ScheduledMatch[];
  eventKey: string;
  author: { uid: string; displayName: string };
  now: Date;
}

export type ScanEntry =
  | {
      ok: true;
      id: string;
      doc: Record<string, unknown>;
      entry: SavedEntry;
    }
  | { ok: false; error: string };

export function scanToEntry(payload: string, ctx: ScanContext): ScanEntry {
  const decoded = decodeQrScout(ctx.config, payload);
  if (decoded === null) {
    return { ok: false, error: "This is not scout data for the current form." };
  }
  const { values } = decoded;
  const typed = String(values[matchCode] ?? "").trim();
  const tbaMatchKey = resolveMatchKey(typed, ctx.schedule);
  if (typed === "" && tbaMatchKey === null) {
    return {
      ok: false,
      error:
        "The scan has no match number, so it cannot be identified. Ask the scout to fill it in and rescan.",
    };
  }
  const id = scanIdFor(
    contentSignature(tbaMatchKey, scanTeam(values), values, decoded.doubles),
  );
  const matchId = matchIdFor(tbaMatchKey, ctx.eventKey, typed);
  const doc = entryDocument({
    id,
    config: ctx.config,
    values,
    matchId,
    tbaMatchKey,
    authorUid: ctx.author.uid,
    authorDisplayName: ctx.author.displayName,
    now: ctx.now,
    rawValues: true,
  });
  const team = Number(doc.teamNumber);
  if (team <= 0) {
    return { ok: false, error: "The scan has no team number." };
  }
  return {
    ok: true,
    id,
    doc,
    entry: {
      id,
      matchId,
      matchRef: matchRefOf(tbaMatchKey, ctx.eventKey, typed),
      matchNumber: typed,
      team,
      tbaMatchKey,
      station: stationOf(values),
      createdAt: String(doc.createdAt),
      savedAt: ctx.now.toISOString(),
      qr: payload,
    },
  };
}

export function alreadyKnown(
  config: ScoutConfig,
  scan: { id: string; entry: SavedEntry },
  payload: string,
  remote: RemoteEntry[],
  local: SavedEntry[],
): boolean {
  if (local.some((e) => e.id === scan.id)) return true;
  return remote.some(
    (e) =>
      e.id === scan.id ||
      (scan.entry.tbaMatchKey !== null &&
        e.tbaMatchKey === scan.entry.tbaMatchKey &&
        encodeQrScout(config, e.fieldValues) === payload),
  );
}
