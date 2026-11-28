import { useSyncExternalStore } from "react";
import { readCache, writeCache } from "../data/cache";
import { type DraftAction, type Rounds, roundOptions } from "./draft";

export interface DraftState {
  actions: DraftAction[];
  rounds: Rounds | null;
  taken: Record<number, string>;
}

const empty: DraftState = { actions: [], rounds: null, taken: {} };
const keyFor = (eventKey: string) => `ss.draft.v1.${eventKey}`;

const states = new Map<string, DraftState>();
const listeners = new Set<() => void>();

function parse(raw: unknown): DraftState {
  if (typeof raw !== "object" || raw === null) return empty;
  const r = raw as Record<string, unknown>;
  const actions = Array.isArray(r.actions)
    ? r.actions.flatMap((a): DraftAction[] => {
        const x = a as { team?: unknown; declined?: unknown } | null;
        return x && typeof x.team === "number"
          ? [{ team: Math.trunc(x.team), declined: x.declined === true }]
          : [];
      })
    : [];
  const rounds = roundOptions.find((n) => n === r.rounds) ?? null;
  const taken: Record<number, string> = {};
  if (typeof r.taken === "object" && r.taken !== null) {
    for (const [team, label] of Object.entries(r.taken)) {
      if (typeof label === "string") taken[Number(team)] = label;
    }
  }
  return { actions, rounds, taken };
}

export function getDraft(eventKey: string): DraftState {
  if (eventKey === "") return empty;
  let state = states.get(eventKey);
  if (!state) {
    state = parse(readCache<unknown>(keyFor(eventKey)));
    states.set(eventKey, state);
  }
  return state;
}

export function setDraft(eventKey: string, next: DraftState) {
  if (eventKey === "") return;
  states.set(eventKey, next);
  writeCache(keyFor(eventKey), next);
  for (const notify of listeners) notify();
}

const subscribe = (notify: () => void) => {
  listeners.add(notify);
  return () => listeners.delete(notify);
};

export const useDraftState = (eventKey: string) =>
  useSyncExternalStore(subscribe, () => getDraft(eventKey));

export function forgetDrafts() {
  states.clear();
  for (const notify of listeners) notify();
}

export const record = (
  eventKey: string,
  team: number,
  declined: boolean,
): void => {
  const state = getDraft(eventKey);
  setDraft(eventKey, {
    ...state,
    actions: [...state.actions, { team, declined }],
  });
};

export function undo(eventKey: string) {
  const state = getDraft(eventKey);
  setDraft(eventKey, { ...state, actions: state.actions.slice(0, -1) });
}

export function setActions(eventKey: string, actions: DraftAction[]) {
  setDraft(eventKey, { ...getDraft(eventKey), actions });
}

export function setRounds(eventKey: string, rounds: Rounds) {
  setDraft(eventKey, { ...getDraft(eventKey), rounds });
}

export function setTaken(eventKey: string, taken: Record<number, string>) {
  const state = getDraft(eventKey);
  if (JSON.stringify(state.taken) === JSON.stringify(taken)) return;
  setDraft(eventKey, { ...state, taken });
}

export function useTaken(eventKey: string): Record<number, string> {
  return useDraftState(eventKey).taken;
}
