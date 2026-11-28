import { enqueueWrite } from "../outbox/outbox";
import type {
  ScoutShifts,
  ShiftRosterEntry,
  ShiftTradeDoc,
  Span,
} from "../scout/credit";
import { schedulePath, tradePath } from "./paths";
import { toDoc } from "./schedule";
import { answeredTrade, newTrade } from "./trades";

export async function saveSchedule(shifts: ScoutShifts, eventKey: string) {
  const path = schedulePath(eventKey);
  await enqueueWrite(path, toDoc(shifts, eventKey, new Date()), "Shift grid");
}

export function requestTrade(input: {
  eventKey: string;
  requester: { uid: string; displayName: string };
  target: ShiftRosterEntry;
  block: Span;
}) {
  const id = crypto.randomUUID();
  return enqueueWrite(
    tradePath(id),
    newTrade({ ...input, id, now: new Date() }),
    "Shift trade request",
  );
}

export function answerTrade(
  trade: ShiftTradeDoc,
  status: "accepted" | "declined" | "cancelled",
) {
  return enqueueWrite(
    tradePath(trade.id),
    answeredTrade(trade, status, new Date()),
    `Shift trade ${status}`,
  );
}
