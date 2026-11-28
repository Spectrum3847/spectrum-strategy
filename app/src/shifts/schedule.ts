import { Timestamp } from "firebase/firestore";
import type { ScoutShifts, ShiftRosterEntry } from "../scout/credit";
import { buildRotations, maxMatchCount, type RedMatches } from "./generate";

export type CellColor = "green" | "white" | "grey" | "red";
export const cellColors: readonly CellColor[] = [
  "green",
  "white",
  "grey",
  "red",
];

export const maxOverrides = 4096;
export const maxRoster = 64;

export interface Author {
  uid: string;
  displayName: string;
}

export interface Cell {
  col: number;
  match: number;
}

const key = (col: number, match: number) => `${col}:${match}`;
const isColor = (v: unknown): v is CellColor =>
  typeof v === "string" && cellColors.includes(v as CellColor);

export function colorAt(
  shifts: ScoutShifts,
  col: number,
  match: number,
): CellColor {
  const painted = shifts.colors.get(key(col, match));
  if (isColor(painted)) return painted;
  const on = shifts.rotations[col]?.blocks.some(
    (b) => match >= b.startMatch && match <= b.endMatch,
  );
  return on ? "green" : "white";
}

export function stationAt(
  shifts: ScoutShifts,
  col: number,
  match: number,
): string | null {
  const block = shifts.rotations[col]?.blocks.find(
    (b) => match >= b.startMatch && match <= b.endMatch,
  );
  return block?.station ?? null;
}

export function labelAt(
  shifts: ScoutShifts,
  col: number,
  match: number,
): string {
  const note = shifts.texts.get(key(col, match)) ?? "";
  if (note !== "" || colorAt(shifts, col, match) !== "green") return note;
  return stationAt(shifts, col, match) ?? "";
}

export const noteAt = (shifts: ScoutShifts, col: number, match: number) =>
  shifts.texts.get(key(col, match)) ?? "";

const editedKeys = (shifts: ScoutShifts) =>
  new Set([
    ...[...shifts.colors].filter(([, c]) => isColor(c)).map(([k]) => k),
    ...shifts.texts.keys(),
  ]);

export const hasRotation = (shifts: ScoutShifts) =>
  shifts.rotations.some((r) => r.blocks.length > 0);

export function blank(input: {
  roster: ShiftRosterEntry[];
  matchCount: number;
  author: Author;
}): ScoutShifts {
  const { roster, author } = input;
  if (input.matchCount > maxMatchCount) {
    throw new RangeError(`matchCount must not exceed ${maxMatchCount}`);
  }
  return {
    roster,
    rotations: roster.map((r) => ({ uid: r.uid, blocks: [] })),
    colors: new Map(),
    texts: new Map(),
    matchCount: Math.max(0, input.matchCount),
    authorUid: author.uid,
    authorDisplayName: author.displayName,
  };
}

export function redMatches(shifts: ScoutShifts): RedMatches {
  const red: RedMatches = new Map();
  for (const [cell, color] of shifts.colors) {
    if (color !== "red") continue;
    const [col, match] = cell.split(":").map(Number);
    if (col === undefined || match === undefined) continue;
    red.set(col, (red.get(col) ?? new Set()).add(match));
  }
  return red;
}

export function generate(shifts: ScoutShifts): ScoutShifts {
  return {
    ...shifts,
    rotations: buildRotations(
      shifts.matchCount,
      shifts.roster,
      redMatches(shifts),
    ),
  };
}

export interface Paint {
  color?: CellColor | null;
  text?: string;
}

export function paint(
  shifts: ScoutShifts,
  cells: Cell[],
  change: Paint,
): ScoutShifts | null {
  const colors = new Map(shifts.colors);
  const texts = new Map(shifts.texts);
  for (const { col, match } of cells) {
    if (col < 0 || col >= shifts.roster.length) continue;
    if (match < 1 || match > shifts.matchCount) continue;
    const k = key(col, match);
    if (change.color === null) colors.delete(k);
    else if (change.color !== undefined) colors.set(k, change.color);
    if (change.text === "") texts.delete(k);
    else if (change.text !== undefined) texts.set(k, change.text);
  }
  const next = { ...shifts, colors, texts };
  return editedKeys(next).size > maxOverrides ? null : next;
}

export function markUnavailable(
  shifts: ScoutShifts,
  col: number,
  from: number,
  to: number,
  on: boolean,
): ScoutShifts | null {
  const cells = cellsBetween({ col, match: from }, { col, match: to });
  if (on) return paint(shifts, cells, { color: "red" });
  const colors = new Map(shifts.colors);
  for (const { col: c, match } of cells) {
    if (colors.get(key(c, match)) === "red") colors.delete(key(c, match));
  }
  return { ...shifts, colors };
}

export function addScouts(
  shifts: ScoutShifts,
  scouts: ShiftRosterEntry[],
): ScoutShifts | null {
  const have = new Set(shifts.roster.map((r) => r.name.toLowerCase()));
  const fresh = scouts.filter((s) => !have.has(s.name.toLowerCase()));
  if (fresh.length === 0) return shifts;
  if (shifts.roster.length + fresh.length > maxRoster) return null;
  return {
    ...shifts,
    roster: [...shifts.roster, ...fresh],
    rotations: [
      ...shifts.roster.map(
        (r, i) => shifts.rotations[i] ?? { uid: r.uid, blocks: [] },
      ),
      ...fresh.map((s) => ({ uid: s.uid, blocks: [] })),
    ],
  };
}

export function cellsBetween(a: Cell, b: Cell): Cell[] {
  const cells: Cell[] = [];
  for (let col = Math.min(a.col, b.col); col <= Math.max(a.col, b.col); col++) {
    for (
      let match = Math.min(a.match, b.match);
      match <= Math.max(a.match, b.match);
      match++
    ) {
      cells.push({ col, match });
    }
  }
  return cells;
}

export function toDoc(
  shifts: ScoutShifts,
  eventKey: string,
  now: Date,
): Record<string, unknown> {
  const cellOverrides = [...editedKeys(shifts)]
    .map((k) => {
      const [col = 0, match = 0] = k.split(":").map(Number);
      return { col, match, k };
    })
    .sort((a, b) => a.col - b.col || a.match - b.match)
    .map(({ col, match, k }) => {
      const color = shifts.colors.get(k);
      return {
        col,
        match,
        text: shifts.texts.get(k) ?? "",
        ...(isColor(color) ? { color } : {}),
      };
    });
  return {
    id: eventKey,
    eventKey,
    matchCount: shifts.matchCount,
    roster: shifts.roster.map((r) => ({ uid: r.uid, name: r.name })),
    rotations: shifts.roster.map((r, i) => ({
      uid: r.uid,
      name: r.name,
      shifts: (shifts.rotations[i]?.blocks ?? []).map((b) => ({
        startMatch: b.startMatch,
        endMatch: b.endMatch,
        ...(b.station ? { station: b.station } : {}),
      })),
    })),
    cellOverrides,
    authorUid: shifts.authorUid,
    authorDisplayName: shifts.authorDisplayName.slice(0, 128),
    updatedAt: now.toISOString(),
    updatedAtTs: Timestamp.fromDate(now),
  };
}
