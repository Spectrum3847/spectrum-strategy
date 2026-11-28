import { useSyncExternalStore } from "react";
import { useTrainingEntries } from "../training/entries";
import {
  isTraining,
  trainingKey,
  useTrainingSession,
} from "../training/session";
import type { Values } from "./config";
import type { StandIn } from "./credit";
import type { SavedRef, ScheduledMatch } from "./schedule";

function read<T>(key: string): T | null {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? null : (JSON.parse(raw) as T);
  } catch {
    return null;
  }
}

function write(key: string, value: unknown) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
  }
}

function remove(key: string) {
  try {
    localStorage.removeItem(key);
  } catch {
  }
}

const keys = {
  station: "ss.scout.station",
  lockedStation: "ss.device.station",
  standIn: "ss.scout.standin",
  event: "ss.event.key",
  config: "ss.scout.config",
  tbaKey: "ss.tba.key",
  saved: "ss.scout.saved",
  draft: "ss.scout.draft",
  schedule: (event: string) => `ss.schedule.${event}`,
};

function deviceValue<T>(key: string) {
  let value = read<T>(key);
  const listeners = new Set<() => void>();
  return {
    get: () => value,
    set(next: T | null) {
      value = next;
      if (next === null) remove(key);
      else write(key, next);
      for (const notify of listeners) notify();
    },
    subscribe(notify: () => void) {
      listeners.add(notify);
      return () => listeners.delete(notify);
    },
  };
}

export const lockedStationStore = deviceValue<string>(keys.lockedStation);
export const standInStore = deviceValue<StandIn>(keys.standIn);

export const useLockedStation = () =>
  useSyncExternalStore(lockedStationStore.subscribe, lockedStationStore.get);
export const useStandIn = () =>
  useSyncExternalStore(standInStore.subscribe, standInStore.get);

const slot = (key: string) =>
  isTraining() ? trainingKey(key.replace(/^ss\./, "")) : key;

export const stationStore = {
  get: () => read<string>(slot(keys.station)),
  set: (station: string) => write(slot(keys.station), station),
};

export const eventKeyStore = {
  get: () => read<string>(keys.event) ?? "",
  set: (key: string) => write(keys.event, key),
};

export const configCache = {
  get: () => read<string>(keys.config),
  set: (json: string) => write(keys.config, json),
};

export const tbaKeyCache = {
  get: () => read<string>(keys.tbaKey),
  set: (key: string) => write(keys.tbaKey, key),
  clear: () => remove(keys.tbaKey),
};

export interface CachedSchedule {
  fetchedAt: string;
  matches: ScheduledMatch[];
}

export const scheduleCache = {
  get: (event: string) => read<CachedSchedule>(keys.schedule(event)),
  set: (event: string, value: CachedSchedule) =>
    write(keys.schedule(event), value),
};

export const draftStore = {
  get: (fingerprint: string): Values | null => {
    const draft = read<{ fingerprint: string; values: Values }>(
      slot(keys.draft),
    );
    return draft?.fingerprint === fingerprint ? draft.values : null;
  },
  getStrokes: (fingerprint: string): unknown => {
    const draft = read<{ fingerprint: string; strokes?: unknown }>(
      slot(keys.draft),
    );
    return draft?.fingerprint === fingerprint ? draft.strokes : undefined;
  },
  set: (fingerprint: string, values: Values, strokes?: unknown) =>
    write(slot(keys.draft), {
      fingerprint,
      values,
      ...(strokes ? { strokes } : {}),
    }),
  clear: () => remove(slot(keys.draft)),
};

export interface SavedEntry extends SavedRef {
  id: string;
  matchId: string;
  matchRef: string;
  matchNumber: string;
  team: number;
  createdAt: string;
  savedAt: string;
  qr?: string;
}

const savedLimit = 400;
const qrKept = 60;
let saved: SavedEntry[] = read<SavedEntry[]>(keys.saved) ?? [];
const listeners = new Set<() => void>();

const withoutQr = ({ qr: _qr, ...rest }: SavedEntry): SavedEntry => rest;

export const savedEntries = {
  get: () => saved,
  add(entry: SavedEntry) {
    saved = [entry, ...saved.filter((e) => e.id !== entry.id)]
      .slice(0, savedLimit)
      .map((e, i) => (i >= qrKept && e.qr !== undefined ? withoutQr(e) : e));
    write(keys.saved, saved);
    for (const notify of listeners) notify();
  },
  remove(id: string) {
    saved = saved.filter((e) => e.id !== id);
    write(keys.saved, saved);
    for (const notify of listeners) notify();
  },
  find: (matchRef: string, team: number) =>
    saved.find((e) => e.matchRef === matchRef && e.team === team),
  subscribe(notify: () => void) {
    listeners.add(notify);
    return () => listeners.delete(notify);
  },
  reload() {
    saved = read<SavedEntry[]>(keys.saved) ?? [];
    for (const notify of listeners) notify();
  },
};

export function useSavedEntries(): SavedEntry[] {
  const live = useSyncExternalStore(savedEntries.subscribe, savedEntries.get);
  const training = useTrainingEntries().saved;
  return useTrainingSession() ? training : live;
}

export const matchRefOf = (
  tbaMatchKey: string | null,
  eventKey: string,
  typedMatch: string,
) => tbaMatchKey ?? `typed:${eventKey}:${typedMatch.trim()}`;
