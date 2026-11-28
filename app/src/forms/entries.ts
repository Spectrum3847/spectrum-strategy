import type { FormEntry, PitEntry, PrescoutEntry } from "../data/parse";
import type { EventTeam } from "../data/tbaEvent";
import type { Values } from "../scout/config";

const newestFirst = (a: FormEntry, b: FormEntry) =>
  b.updatedAt.localeCompare(a.updatedAt);

const unique = (names: string[]) => [...new Set(names.filter((n) => n !== ""))];

const inPitEvent = (e: FormEntry, eventKey: string) =>
  e.eventKey === eventKey || e.eventKey === "";

export function ownPitEntry(
  entries: PitEntry[],
  team: number,
  uid: string | null,
  eventKey: string,
): PitEntry | null {
  if (uid === null) return null;
  const mine = entries
    .filter(
      (e) =>
        e.teamNumber === team && e.authorUid === uid && inPitEvent(e, eventKey),
    )
    .sort(newestFirst);
  return mine.find((e) => e.eventKey === eventKey) ?? mine[0] ?? null;
}

export function pitEntriesFor(
  entries: PitEntry[],
  team: number,
  eventKey: string,
): PitEntry[] {
  return entries
    .filter((e) => e.teamNumber === team && inPitEvent(e, eventKey))
    .sort(newestFirst);
}

export interface PitRow {
  team: number;
  name: string;
  done: boolean;
  state: string;
  scouts: string[];
}

const isAnswer = (v: unknown) =>
  v !== undefined &&
  v !== null &&
  v !== "" &&
  v !== false &&
  !(Array.isArray(v) && v.length === 0);

export const hasAnswers = (e: FormEntry) =>
  Object.values(e.fieldValues).some(isAnswer);

export function pitState(found: PitEntry[]): { done: boolean; state: string } {
  const form = found.some(hasAnswers);
  const photo = found.some((e) => e.photoKeys.length > 0);
  if (form && photo) return { done: true, state: "Done" };
  if (form) return { done: false, state: "Form done, no photo" };
  if (photo) return { done: false, state: "Photo, no form" };
  return { done: false, state: "Not done" };
}

export function pitRows(
  teams: EventTeam[],
  entries: PitEntry[],
  eventKey: string,
): PitRow[] {
  return teams.map((t) => {
    const found = pitEntriesFor(entries, t.number, eventKey);
    return {
      team: t.number,
      name: t.nickname,
      ...pitState(found),
      scouts: unique(found.map((e) => e.scoutName)),
    };
  });
}

export const prescoutPerTeam = 5;

export function prescoutMatchLabel(type: unknown, number: unknown): string {
  const n = String(number ?? "").trim();
  if (n === "") return "";
  switch (String(type ?? "")) {
    case "qual":
      return `Q${n}`;
    case "playoff":
      return `Playoff ${n}`;
    case "final":
      return `Final ${n}`;
    default:
      return n;
  }
}

export const entryMatchLabel = (e: { fieldValues: Values }) =>
  prescoutMatchLabel(e.fieldValues.matchType, e.fieldValues.matchNumber);

const normalized = (v: unknown) =>
  String(v ?? "")
    .trim()
    .toLowerCase();

export const watchedMatchId = (event: unknown, label: string) =>
  `${normalized(event)}|${normalized(label)}`;

export function prescoutRecords(
  entries: PrescoutEntry[],
  team: number,
  eventKey: string,
): PrescoutEntry[] {
  return entries
    .filter((e) => e.teamNumber === team && e.eventKey === eventKey)
    .sort((a, b) => a.updatedAt.localeCompare(b.updatedAt));
}

export interface PrescoutRow {
  team: number;
  name: string;
  count: number;
  complete: boolean;
  starter: string | null;
}

export function prescoutRows(
  teams: EventTeam[],
  entries: PrescoutEntry[],
  eventKey: string,
): PrescoutRow[] {
  return teams.map((t) => {
    const found = prescoutRecords(entries, t.number, eventKey);
    return {
      team: t.number,
      name: t.nickname,
      count: found.length,
      complete: found.length >= prescoutPerTeam,
      starter: found[0]?.scoutName || null,
    };
  });
}

export function isDuplicateRecord(
  entries: PrescoutEntry[],
  team: number,
  eventKey: string,
  values: Values,
  ownId: string,
): boolean {
  const label = prescoutMatchLabel(values.matchType, values.matchNumber);
  if (label === "") return false;
  const wanted = watchedMatchId(values.watchedEvent, label);
  return prescoutRecords(entries, team, eventKey).some(
    (e) =>
      e.id !== ownId &&
      watchedMatchId(e.fieldValues.watchedEvent, entryMatchLabel(e)) === wanted,
  );
}

export function splitLegacyLabel(values: Values): Values {
  if (values.matchType !== undefined && values.matchType !== null) {
    return values;
  }
  const m = /^(Q|Playoff |Final )(\d+)$/i.exec(
    String(values.matchNumber ?? "").trim(),
  );
  if (!m) return values;
  const kind = (m[1] ?? "").trim().toLowerCase();
  return {
    ...values,
    matchType: kind === "q" ? "qual" : kind,
    matchNumber: m[2],
  };
}
