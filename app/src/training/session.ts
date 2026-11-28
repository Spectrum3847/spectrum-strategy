import { useSyncExternalStore } from "react";
import { readCache, writeCache } from "../data/cache";
import type { Replay } from "./replay";

export const trainingPrefix = "ss.training.";
export const trainingKey = (name: string) => `${trainingPrefix}${name}`;

export class TrainingWriteError extends Error {
  constructor() {
    super("Training mode: nothing is saved to the team database.");
    this.name = "TrainingWriteError";
  }
}

export interface TrainingSession {
  eventKey: string;
  revealed: number;
  startedAt: string;
  replay: Replay;
}

const sessionKey = trainingKey("session");

function load(): TrainingSession | null {
  const raw = readCache<Partial<TrainingSession>>(sessionKey);
  if (
    !raw ||
    typeof raw.eventKey !== "string" ||
    typeof raw.revealed !== "number" ||
    !Array.isArray(raw.replay?.matches) ||
    !Array.isArray(raw.replay?.teams)
  ) {
    return null;
  }
  return raw as TrainingSession;
}

let session = load();
const listeners = new Set<() => void>();

function set(next: TrainingSession | null) {
  session = next;
  if (next) writeCache(sessionKey, next);
  else clearTrainingKeys();
  for (const notify of listeners) notify();
}

export function clearTrainingKeys() {
  try {
    for (const key of Object.keys(localStorage)) {
      if (key.startsWith(trainingPrefix)) localStorage.removeItem(key);
    }
  } catch {
  }
}

export const isTraining = () => session !== null;
export const getSession = () => session;

export const subscribeSession = (notify: () => void) => {
  listeners.add(notify);
  return () => listeners.delete(notify);
};

export const useTrainingSession = () =>
  useSyncExternalStore(subscribeSession, getSession);

export function startTraining(eventKey: string, replay: Replay) {
  set({
    eventKey,
    revealed: 0,
    startedAt: new Date().toISOString(),
    replay,
  });
}

export function playNextMatch() {
  if (!session || session.revealed >= session.replay.matches.length) return;
  set({ ...session, revealed: session.revealed + 1 });
}

export function leaveTraining() {
  set(null);
}

export function restartTraining() {
  if (!session) return;
  const { eventKey, replay } = session;
  clearTrainingKeys();
  set({ eventKey, revealed: 0, startedAt: new Date().toISOString(), replay });
}
