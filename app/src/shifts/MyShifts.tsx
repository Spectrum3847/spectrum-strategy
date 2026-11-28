import { type FormEvent, useState } from "react";
import type {
  ScoutShifts,
  ShiftRosterEntry,
  ShiftTradeDoc,
  Span,
} from "../scout/credit";
import { awayText, type MyBlock, rangeText } from "./mine";
import { sameSpan, tradeTargets } from "./trades";

export interface Delivery {
  id: string;
  status: "on-device" | "sending" | "in-database" | "refused";
  error?: string;
}

const statusText = {
  "on-device": "On this device",
  sending: "Sending",
  "in-database": "In the database",
  refused: "Refused",
} as const;

export function DeliveryState({
  delivery,
  onDismiss,
}: {
  delivery: Delivery | undefined;
  onDismiss(id: string): void;
}) {
  if (!delivery) return null;
  return (
    <span className="delivery">
      <span className="state" data-state={delivery.status}>
        {statusText[delivery.status]}
      </span>
      {delivery.status === "refused" && (
        <>
          {delivery.error && (
            <span className="secondary">{delivery.error}</span>
          )}
          <button
            type="button"
            className="link-btn"
            onClick={() => onDismiss(delivery.id)}
          >
            Dismiss
          </button>
        </>
      )}
    </span>
  );
}

const stationSide = (station: string) =>
  station.startsWith("R") ? "red" : "blue";

function TradeForm({
  block,
  targets,
  onSend,
  onClose,
}: {
  block: Span;
  targets: ShiftRosterEntry[];
  onSend(target: ShiftRosterEntry): void;
  onClose(): void;
}) {
  const [uid, setUid] = useState("");
  const submit = (e: FormEvent) => {
    e.preventDefault();
    const target = targets.find((t) => t.uid === uid);
    if (target) onSend(target);
  };
  return (
    <form className="trade-form" onSubmit={submit}>
      <label className="field-name" htmlFor="trade-target">
        Ask who to cover {rangeText(block)}?
      </label>
      <select
        id="trade-target"
        className="input"
        value={uid}
        onChange={(e) => setUid(e.target.value)}
      >
        <option value="">Pick a scout</option>
        {targets.map((t) => (
          <option key={t.uid} value={t.uid}>
            {t.name}
          </option>
        ))}
      </select>
      <div className="actions">
        <button type="submit" className="btn primary" disabled={uid === ""}>
          Send request
        </button>
        <button type="button" className="btn" onClick={onClose}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export interface MyShiftsProps {
  uid: string;
  name: string;
  blocks: MyBlock[] | null;
  shifts: ScoutShifts;
  trades: ShiftTradeDoc[];
  onRequestTrade(block: Span, target: ShiftRosterEntry): void;
}

export function MyShifts({
  uid,
  name,
  blocks,
  shifts,
  trades,
  onRequestTrade,
}: MyShiftsProps) {
  const [open, setOpen] = useState<Span | null>(null);
  if (blocks === null) {
    const own = name.trim().toLowerCase();
    const unlinked =
      own !== "" &&
      shifts.roster.some(
        (r) => r.uid === "" && r.name.trim().toLowerCase() === own,
      );
    return (
      <p>
        {unlinked
          ? "No column on this grid is linked to your account, so your shifts are not shown and you cannot trade. Ask a strategy lead to check that your name on the grid matches your account name."
          : "You are not on this schedule."}
      </p>
    );
  }
  if (blocks.length === 0) return <p>You have no shifts on this schedule.</p>;
  const targets = tradeTargets(shifts, uid);
  const askedOf = (block: Span) =>
    trades.find(
      (t) =>
        t.status === "pending" &&
        t.requesterUid === uid &&
        sameSpan(t.requesterBlock, block),
    );
  return (
    <ul className="my-shifts">
      {blocks.map(({ block, tradedWith, away }) => {
        const asked = askedOf(block);
        const isOpen = open !== null && sameSpan(open, block);
        return (
          <li
            key={`${block.startMatch}-${block.endMatch}`}
            data-done={away === "done" ? "" : undefined}
          >
            <div className="shift-line">
              <strong>{rangeText(block)}</strong>
              {block.station && (
                <span
                  className="tag"
                  data-alliance={stationSide(block.station)}
                >
                  {block.station}
                </span>
              )}
              <span className="secondary">{awayText(away)}</span>
            </div>
            {tradedWith !== null && (
              <p className="secondary">
                Traded with {tradedWith || "a teammate"}
              </p>
            )}
            {asked ? (
              <p className="secondary">
                Waiting for {asked.targetDisplayName || "a teammate"} to answer
              </p>
            ) : isOpen ? (
              <TradeForm
                block={block}
                targets={targets}
                onSend={(target) => {
                  setOpen(null);
                  onRequestTrade(block, target);
                }}
                onClose={() => setOpen(null)}
              />
            ) : (
              away !== "done" &&
              targets.length > 0 && (
                <button
                  type="button"
                  className="btn"
                  onClick={() => setOpen(block)}
                >
                  Trade this shift
                </button>
              )
            )}
          </li>
        );
      })}
    </ul>
  );
}
