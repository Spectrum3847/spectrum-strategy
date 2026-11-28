import type { OutboxStatus } from "../outbox/confirm";

export interface Unsent {
  pending: number;
  refused: number;
}

export function unsentCounts(items: { status: OutboxStatus }[]): Unsent {
  let pending = 0;
  let refused = 0;
  for (const { status } of items) {
    if (status === "on-device" || status === "sending") pending += 1;
    else if (status === "refused") refused += 1;
  }
  return { pending, refused };
}

export const unsentTotal = (u: Unsent) => u.pending + u.refused;

export function unsentLines(u: Unsent, online: boolean): string[] {
  const lines: string[] = [];
  if (u.pending > 0) {
    const verb = u.pending === 1 ? "entry is" : "entries are";
    lines.push(
      `${u.pending} ${verb} saved on this device and not in the database yet.${
        online ? "" : " They send when this device is back online."
      }`,
    );
  }
  if (u.refused > 0) {
    const verb = u.refused === 1 ? "entry was" : "entries were";
    lines.push(`${u.refused} ${verb} refused by the database.`);
  }
  return lines;
}
