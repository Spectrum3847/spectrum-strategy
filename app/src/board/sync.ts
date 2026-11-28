import type { OutboxStatus } from "../outbox/confirm";

export type RemoteDecision = "ignore" | "adopt" | "defer" | "conflict";

export function decideRemote(input: {
  mine: number;
  theirs: number;
  unsent: boolean;
  drawing: boolean;
}): RemoteDecision {
  if (input.theirs <= input.mine) return "ignore";
  if (input.unsent) return "conflict";
  return input.drawing ? "defer" : "adopt";
}

export type DeliveryKind =
  | "none"
  | "failed"
  | "device"
  | "waiting"
  | "sending"
  | "database"
  | "copy"
  | "refused";

export interface DeliveryState {
  kind: DeliveryKind;
  text: string;
}

export interface DeliveryInput {
  hasBoard: boolean;
  local: "saved" | "saving" | "failed";
  handed: boolean;
  signedIn: boolean;
  item: { status: OutboxStatus; error?: string } | undefined;
  remote: "none" | "server" | "cache";
}

export function deliveryState(i: DeliveryInput): DeliveryState {
  if (i.local === "failed") {
    return {
      kind: "failed",
      text: "Not saved on this device. Free some storage and draw again.",
    };
  }
  if (!i.hasBoard) {
    return {
      kind: "none",
      text: "Nothing drawn yet. Drawings save on this device first.",
    };
  }
  if (i.local === "saving") {
    return { kind: "device", text: "Saving on this device" };
  }
  if (!i.handed || (i.item === undefined && i.remote === "none")) {
    return i.signedIn
      ? { kind: "device", text: "Saved on this device" }
      : { kind: "waiting", text: "Saved on this device, waiting for sign-in" };
  }
  if (i.item === undefined) {
    return i.remote === "server"
      ? { kind: "database", text: "In the database" }
      : {
          kind: "copy",
          text: "Showing the last copy this device received from the database",
        };
  }
  switch (i.item.status) {
    case "in-database":
      return { kind: "database", text: "In the database" };
    case "refused":
      return {
        kind: "refused",
        text: `Refused by the database${i.item.error ? `: ${i.item.error}` : ""}`,
      };
    case "sending":
      return i.signedIn
        ? { kind: "sending", text: "Sending to the database" }
        : {
            kind: "waiting",
            text: "Saved on this device, waiting for sign-in",
          };
    default:
      return i.signedIn
        ? { kind: "device", text: "Saved on this device, not sent yet" }
        : {
            kind: "waiting",
            text: "Saved on this device, waiting for sign-in",
          };
  }
}
