import { Timestamp } from "firebase/firestore";
import type {
  ScoutShifts,
  ShiftRosterEntry,
  ShiftTradeDoc,
  Span,
  TradeStatus,
} from "../scout/credit";

export const spanOf = (b: Span): Span => ({
  startMatch: b.startMatch,
  endMatch: b.endMatch,
});

export const sameSpan = (a: Span, b: Span) =>
  a.startMatch === b.startMatch && a.endMatch === b.endMatch;

export function newTrade(input: {
  id: string;
  eventKey: string;
  requester: { uid: string; displayName: string };
  target: ShiftRosterEntry;
  block: Span;
  now: Date;
}): Record<string, unknown> {
  const iso = input.now.toISOString();
  return {
    id: input.id,
    eventKey: input.eventKey,
    requesterUid: input.requester.uid,
    requesterDisplayName: input.requester.displayName.slice(0, 128),
    targetUid: input.target.uid,
    targetDisplayName: input.target.name.slice(0, 128),
    requesterBlock: spanOf(input.block),
    status: "pending",
    createdAt: iso,
    updatedAt: iso,
    updatedAtTs: Timestamp.fromDate(input.now),
  };
}

export function answeredTrade(
  trade: ShiftTradeDoc,
  status: Exclude<TradeStatus, "pending">,
  now: Date,
): Record<string, unknown> {
  return {
    ...trade.source,
    status,
    updatedAt: now.toISOString(),
    updatedAtTs: Timestamp.fromDate(now),
  };
}

export const pendingFor = (trades: ShiftTradeDoc[], uid: string | null) =>
  uid
    ? trades.filter(
        (t) =>
          t.id !== "" &&
          t.status === "pending" &&
          (t.requesterUid === uid || t.targetUid === uid),
      )
    : [];

export function tradedWith(
  trades: ShiftTradeDoc[],
  uid: string,
): Array<{ block: Span; name: string }> {
  const out: Array<{ block: Span; name: string }> = [];
  for (const t of trades) {
    if (t.status !== "accepted") continue;
    if (t.requesterUid === uid && t.targetBlock) {
      out.push({ block: t.targetBlock, name: t.targetDisplayName });
    } else if (t.targetUid === uid) {
      out.push({ block: t.requesterBlock, name: t.requesterDisplayName });
    }
  }
  return out;
}

export function tradeTargets(
  shifts: ScoutShifts,
  uid: string,
): ShiftRosterEntry[] {
  const seen = new Set<string>();
  return shifts.roster.filter((r) => {
    if (r.uid === "" || r.uid === uid || r.name === "" || seen.has(r.uid)) {
      return false;
    }
    seen.add(r.uid);
    return true;
  });
}
