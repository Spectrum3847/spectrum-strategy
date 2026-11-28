import { normalizeStation } from "./config";

const standInLength = 6;

export interface ShiftRosterEntry {
  uid: string;
  name: string;
}

export interface ShiftBlock {
  startMatch: number;
  endMatch: number;
  station: string | null;
}

export interface ShiftRotation {
  uid: string;
  blocks: ShiftBlock[];
}

export interface ScoutShifts {
  roster: ShiftRosterEntry[];
  rotations: ShiftRotation[];
  colors: Map<string, string>;
  texts: Map<string, string>;
  matchCount: number;
  authorUid: string;
  authorDisplayName: string;
}

export interface ShiftTrade {
  requesterUid: string;
  targetUid: string;
  requesterBlock: Span;
  targetBlock: Span | null;
  createdAt: number;
}

export interface Span {
  startMatch: number;
  endMatch: number;
}

export interface Credit {
  name: string;
  uid: string;
  standIn: boolean;
}

export interface StandIn {
  eventKey: string;
  station: string;
  name: string;
  uid: string;
  fromMatch: number;
  untilMatch: number;
}

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

const text = (v: unknown) => (typeof v === "string" ? v.trim() : "");
const int = (v: unknown) => (typeof v === "number" ? Math.trunc(v) : 0);
const list = (v: unknown) => (Array.isArray(v) ? v : []);

export function parseShifts(data: unknown): ScoutShifts | null {
  if (!isRecord(data)) return null;
  const roster = list(data.roster).filter(isRecord).map(rosterEntry);
  if (roster.length === 0) return null;
  const rotations = list(data.rotations).map(rotation).slice(0, roster.length);
  const colors = new Map<string, string>();
  const texts = new Map<string, string>();
  for (const edit of list(data.cellOverrides).filter(isRecord)) {
    const key = `${int(edit.col)}:${int(edit.match)}`;
    if (typeof edit.color === "string") colors.set(key, edit.color);
    if (typeof edit.text === "string" && edit.text !== "") {
      texts.set(key, edit.text);
    }
  }
  return {
    roster,
    rotations,
    colors,
    texts,
    matchCount: Math.max(0, int(data.matchCount)),
    authorUid: typeof data.authorUid === "string" ? data.authorUid : "",
    authorDisplayName:
      typeof data.authorDisplayName === "string" ? data.authorDisplayName : "",
  };
}

function rosterEntry(r: Record<string, unknown>): ShiftRosterEntry {
  return { uid: text(r.uid), name: text(r.name) };
}

function rotation(r: unknown): ShiftRotation {
  if (!isRecord(r)) return { uid: "", blocks: [] };
  return {
    uid: text(r.uid),
    blocks: list(r.shifts)
      .filter(isRecord)
      .map((s) => ({
        startMatch: int(s.startMatch),
        endMatch: int(s.endMatch),
        station: normalizeStation(text(s.station)),
      })),
  };
}

function span(v: unknown): Span | null {
  if (!isRecord(v)) return null;
  const startMatch = int(v.startMatch);
  const endMatch = int(v.endMatch);
  return startMatch >= 1 && endMatch >= startMatch
    ? { startMatch, endMatch }
    : null;
}

export type TradeStatus = "pending" | "accepted" | "declined" | "cancelled";

const tradeStatuses: readonly string[] = [
  "pending",
  "accepted",
  "declined",
  "cancelled",
];

export interface ShiftTradeDoc {
  id: string;
  eventKey: string;
  requesterUid: string;
  requesterDisplayName: string;
  targetUid: string;
  targetDisplayName: string;
  requesterBlock: Span;
  targetBlock: Span | null;
  status: TradeStatus;
  createdAt: string;
  source: Record<string, unknown>;
}

const raw = (v: unknown) => (typeof v === "string" ? v : "");
const stamp = (iso: string) => {
  const ms = Date.parse(iso.trim());
  return Number.isNaN(ms) ? 0 : ms;
};

export function parseTradeDocs(docs: unknown[]): ShiftTradeDoc[] {
  const trades: ShiftTradeDoc[] = [];
  for (const d of docs) {
    if (!isRecord(d)) continue;
    const requesterBlock = span(d.requesterBlock);
    if (!requesterBlock) continue;
    trades.push({
      id: raw(d.id),
      eventKey: raw(d.eventKey),
      requesterUid: raw(d.requesterUid),
      requesterDisplayName: raw(d.requesterDisplayName),
      targetUid: raw(d.targetUid),
      targetDisplayName: raw(d.targetDisplayName),
      requesterBlock,
      targetBlock: span(d.targetBlock),
      status: tradeStatuses.includes(raw(d.status))
        ? (d.status as TradeStatus)
        : "pending",
      createdAt: raw(d.createdAt),
      source: d,
    });
  }
  return trades.sort((a, b) => stamp(b.createdAt) - stamp(a.createdAt));
}

export function acceptedTrades(trades: ShiftTradeDoc[]): ShiftTrade[] {
  return trades
    .filter((t) => t.status === "accepted")
    .map((t) => ({
      requesterUid: t.requesterUid.trim(),
      targetUid: t.targetUid.trim(),
      requesterBlock: t.requesterBlock,
      targetBlock: t.targetBlock,
      createdAt: stamp(t.createdAt),
    }));
}

export const parseTrades = (docs: unknown[]): ShiftTrade[] =>
  acceptedTrades(parseTradeDocs(docs));

const sameSpan = (a: Span, b: Span) =>
  a.startMatch === b.startMatch && a.endMatch === b.endMatch;

export function applyTrades(
  shifts: ScoutShifts,
  trades: ShiftTrade[],
): ScoutShifts {
  if (trades.length === 0) return shifts;
  const rotations = shifts.rotations.map((r) => ({ ...r }));
  const move = (fromUid: string, toUid: string, block: Span) => {
    if (fromUid === "" || toUid === "") return;
    const from = rotations.findIndex((r) => r.uid === fromUid);
    const to = rotations.findIndex((r) => r.uid === toUid);
    const giver = rotations[from];
    const taker = rotations[to];
    if (!giver || !taker) return;
    const given = giver.blocks.find((b) => sameSpan(b, block));
    if (!given) return;
    const station = given.station;
    giver.blocks = giver.blocks.filter((b) => !sameSpan(b, block));
    taker.blocks = [...taker.blocks, { ...block, station }];
  };
  for (const trade of trades) {
    move(trade.requesterUid, trade.targetUid, trade.requesterBlock);
    if (trade.targetBlock) {
      move(trade.targetUid, trade.requesterUid, trade.targetBlock);
    }
  }
  return { ...shifts, rotations };
}

interface Scheduled {
  name: string;
  uid: string;
}

export function scheduledScout(
  shifts: ScoutShifts,
  station: string,
  match: number,
): Scheduled | null {
  const wanted = normalizeStation(station);
  if (wanted === null) return null;
  const found = new Map<number, Scheduled>();
  shifts.rotations.forEach((rot, col) => {
    const entry = shifts.roster[col];
    if (!entry || entry.name === "") return;
    const on = rot.blocks.some(
      (b) =>
        b.station === wanted && match >= b.startMatch && match <= b.endMatch,
    );
    const painted = shifts.colors.get(`${col}:${match}`);
    if (on && (painted === undefined || painted === "green")) {
      found.set(col, { name: entry.name, uid: entry.uid });
    }
  });
  const [only, ...rest] = [...found.values()];
  return only && rest.length === 0 ? only : null;
}

function shiftEnd(
  shifts: ScoutShifts,
  station: string,
  match: number,
): number | null {
  const wanted = normalizeStation(station);
  let end: number | null = null;
  for (const rot of shifts.rotations) {
    for (const b of rot.blocks) {
      if (b.station !== wanted || match < b.startMatch || match > b.endMatch) {
        continue;
      }
      end = end === null ? b.endMatch : Math.min(end, b.endMatch);
    }
  }
  return end;
}

export function standInApplies(
  standIn: StandIn | null,
  eventKey: string,
  station: string,
  match: number,
): standIn is StandIn {
  const normalized = normalizeStation(station);
  return (
    standIn !== null &&
    standIn.eventKey === eventKey &&
    normalized !== null &&
    normalizeStation(standIn.station) === normalized &&
    match >= standIn.fromMatch &&
    match <= standIn.untilMatch
  );
}

export function creditFor(input: {
  shifts: ScoutShifts | null;
  station: string | null;
  match: number | null;
  eventKey: string;
  standIn: StandIn | null;
}): Credit | null {
  const { shifts, station, match, eventKey, standIn } = input;
  if (!shifts || !station || match === null) return null;
  if (standInApplies(standIn, eventKey, station, match)) {
    return { name: standIn.name, uid: standIn.uid, standIn: true };
  }
  const scheduled = scheduledScout(shifts, station, match);
  return scheduled
    ? { name: scheduled.name, uid: scheduled.uid, standIn: false }
    : null;
}

export function startStandIn(input: {
  shifts: ScoutShifts;
  station: string;
  match: number;
  eventKey: string;
  who: { name: string; uid: string };
}): StandIn {
  const { shifts, station, match } = input;
  return {
    eventKey: input.eventKey,
    station: normalizeStation(station) ?? station,
    name: input.who.name.trim().slice(0, 128),
    uid: input.who.uid.slice(0, 128),
    fromMatch: match,
    untilMatch: Math.min(
      shiftEnd(shifts, station, match) ?? Number.POSITIVE_INFINITY,
      match + standInLength - 1,
    ),
  };
}

export function rosterNames(shifts: ScoutShifts): ShiftRosterEntry[] {
  const seen = new Set<string>();
  return shifts.roster.filter((r) => {
    const key = r.name.toLowerCase();
    if (r.name === "" || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

export const matchNumberOf = (typed: string): number | null => {
  const n = Number.parseInt(typed.trim(), 10);
  return Number.isInteger(n) && n > 0 ? n : null;
};
