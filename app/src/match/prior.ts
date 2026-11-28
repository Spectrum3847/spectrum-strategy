import { matchOrder } from "../data/matchKey";
import type { EventEntry } from "../data/parse";
import { entryMatchKey } from "../team/stats";

function entryOrder(entry: EventEntry): number {
  const key = entryMatchKey(entry);
  if (key.startsWith("typed:")) {
    return matchOrder(`typed_qm${key.slice("typed:".length)}`);
  }
  return matchOrder(key);
}

export function entriesBefore(
  entries: EventEntry[],
  matchKey: string,
): EventEntry[] {
  const at = matchOrder(matchKey);
  return entries.filter((e) => entryOrder(e) < at);
}

export function entriesIn(
  entries: EventEntry[],
  matchKey: string,
): EventEntry[] {
  const key = matchKey.toLowerCase();
  return entries.filter((e) => entryMatchKey(e) === key);
}
