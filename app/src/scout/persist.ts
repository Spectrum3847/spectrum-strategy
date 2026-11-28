import { enqueueDelete, enqueueWrite, type OutboxItem } from "../outbox/outbox";
import { addTrainingEntry } from "../training/entries";
import { isTraining } from "../training/session";
import { type SavedEntry, savedEntries } from "./local";
import type { Delivery } from "./ScoutForm";

export async function persistEntry(
  doc: Record<string, unknown>,
  entry: SavedEntry,
): Promise<void> {
  if (isTraining()) {
    addTrainingEntry(doc, entry);
    return;
  }
  await enqueueWrite(
    `scoutEntries/${entry.id}`,
    doc,
    `Team ${entry.team}, match ${entry.matchNumber}`,
  );
  savedEntries.add(entry);
}

export async function removeEntry(entry: SavedEntry): Promise<void> {
  await enqueueDelete(
    `scoutEntries/${entry.id}`,
    `Team ${entry.team}, match ${entry.matchNumber} deleted`,
  );
  savedEntries.remove(entry.id);
}

export function deliveryFrom(outbox: OutboxItem[]) {
  return (id: string): Delivery | undefined => {
    if (isTraining()) return { status: "on-device", training: true };
    const item = outbox.find((i) => i.path === `scoutEntries/${id}`);
    if (!item) return undefined;
    return {
      status: item.status,
      ...(item.error ? { error: item.error } : {}),
    };
  };
}
