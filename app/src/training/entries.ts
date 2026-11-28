import { useSyncExternalStore } from "react";
import { readCache, writeCache } from "../data/cache";
import { type EventEntry, parseEventEntry } from "../data/parse";
import { encodeData } from "../outbox/serialize";
import type { SavedEntry } from "../scout/local";
import { subscribeSession, trainingKey } from "./session";

interface Stored {
  doc: Record<string, unknown>;
  saved: SavedEntry;
}

export interface TrainingEntries {
  entries: EventEntry[];
  saved: SavedEntry[];
}

const key = trainingKey("entries");
const cap = 600;

const read = () => readCache<Stored[]>(key) ?? [];

let list = read();
let view: TrainingEntries | null = null;
const listeners = new Set<() => void>();

function changed(next: Stored[]) {
  list = next;
  view = null;
  for (const notify of listeners) notify();
}

subscribeSession(() => changed(read()));

export function addTrainingEntry(
  doc: Record<string, unknown>,
  saved: SavedEntry,
) {
  const { qr: _qr, ...entry } = saved;
  const next = [
    { doc: encodeData(doc) as Record<string, unknown>, saved: entry },
    ...list.filter((s) => s.saved.id !== entry.id),
  ].slice(0, cap);
  writeCache(key, next);
  changed(next);
}

export function trainingEntries(): TrainingEntries {
  view ??= {
    entries: list.map((s) => parseEventEntry(s.saved.id, s.doc)),
    saved: list.map((s) => s.saved),
  };
  return view;
}

export const useTrainingEntries = () =>
  useSyncExternalStore((notify) => {
    listeners.add(notify);
    return () => listeners.delete(notify);
  }, trainingEntries);
