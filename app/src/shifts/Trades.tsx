import type { ShiftTradeDoc } from "../scout/credit";
import { type Delivery, DeliveryState } from "./MyShifts";
import { rangeText } from "./mine";
import { tradePath } from "./paths";

const name = (n: string) => n || "A teammate";

export function tradeLine(t: ShiftTradeDoc, uid: string): string {
  const range = rangeText(t.requesterBlock);
  const asked = uid === t.requesterUid;
  switch (t.status) {
    case "pending":
      return asked
        ? `You asked ${name(t.targetDisplayName)} to cover ${range}.`
        : `${name(t.requesterDisplayName)} asks you to cover ${range}.`;
    case "accepted":
      return asked
        ? `${name(t.targetDisplayName)} took ${range}.`
        : `You took ${range} from ${name(t.requesterDisplayName)}.`;
    case "declined":
      return asked
        ? `${name(t.targetDisplayName)} declined ${range}.`
        : `You declined ${range} from ${name(t.requesterDisplayName)}.`;
    case "cancelled":
      return asked
        ? `You cancelled your request for ${range}.`
        : `${name(t.requesterDisplayName)} cancelled the request for ${range}.`;
  }
}

const recentCount = 5;

export interface TradesProps {
  uid: string;
  trades: ShiftTradeDoc[];
  deliveryOf(path: string): Delivery | undefined;
  onDismiss(id: string): void;
  onAnswer(
    trade: ShiftTradeDoc,
    status: "accepted" | "declined" | "cancelled",
  ): void;
}

export function Trades({
  uid,
  trades,
  deliveryOf,
  onDismiss,
  onAnswer,
}: TradesProps) {
  const pending = trades.filter((t) => t.status === "pending");
  const done = trades
    .filter((t) => t.status !== "pending")
    .slice(0, recentCount);
  return (
    <ul className="trade-list">
      {[...pending, ...done].map((t) => (
        <li key={t.id}>
          <p>{tradeLine(t, uid)}</p>
          {t.status === "pending" && (
            <div className="actions">
              {t.targetUid === uid ? (
                <>
                  <button
                    type="button"
                    className="btn primary"
                    onClick={() => onAnswer(t, "accepted")}
                  >
                    Take it
                  </button>
                  <button
                    type="button"
                    className="btn"
                    onClick={() => onAnswer(t, "declined")}
                  >
                    Decline
                  </button>
                </>
              ) : (
                <button
                  type="button"
                  className="btn"
                  onClick={() => onAnswer(t, "cancelled")}
                >
                  Cancel request
                </button>
              )}
            </div>
          )}
          <DeliveryState
            delivery={deliveryOf(tradePath(t.id))}
            onDismiss={onDismiss}
          />
        </li>
      ))}
    </ul>
  );
}
