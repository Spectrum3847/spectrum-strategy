import type { PitEntry } from "../data/parse";
import { pitEntriesFor } from "../forms/entries";
import { type PhotoItem, waitingEntry } from "./state";

export function placements(
  items: readonly PhotoItem[],
  entries: readonly PitEntry[],
): Map<string, string> {
  const moves = new Map<string, string>();
  for (const item of items) {
    if (item.entryId !== waitingEntry) continue;
    const target = pitEntriesFor(
      [...entries],
      item.team,
      item.eventKey ?? "",
    )[0];
    if (target) moves.set(item.id, target.id);
  }
  return moves;
}
