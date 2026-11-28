import { useMemo } from "react";
import { useScoutData } from "../scout/ScoutData";
import type { ScheduledMatch } from "../scout/schedule";
import { useTrainingView } from "../training/view";
import { readCache, writeCache } from "./cache";
import { type CompLevel, matchOrder } from "./matchKey";
import { registerRefresh } from "./refresh";
import { createStore, type Store, storeFor, useStore } from "./store";
import {
  type EventMatch,
  fetchEventSnapshot,
  type TbaEventSnapshot,
} from "./tbaEvent";
import { teamKey } from "./tbaKey";

export type TbaStatus = "none" | "loading" | "ready" | "failed";

interface TbaState {
  status: TbaStatus;
  snapshot: TbaEventSnapshot | null;
}

const idle: TbaState = { status: "none", snapshot: null };
const cacheKey = (event: string) => `ss.tba.event.${event}`;
const refreshMs = 5 * 60_000;

function eventStore(eventKey: string): Store<TbaState> {
  const cached = readCache<TbaEventSnapshot>(cacheKey(eventKey));
  const initial: TbaState = cached
    ? { status: "ready", snapshot: cached }
    : { status: "none", snapshot: null };
  return createStore(initial, (set, get) => {
    let running = false;
    let live = true;
    const refresh = async () => {
      if (running) return;
      running = true;
      if (get().status !== "ready") set({ ...get(), status: "loading" });
      try {
        const apiKey = await teamKey();
        if (!apiKey) throw new Error("No TBA key available");
        const snapshot = await fetchEventSnapshot(
          eventKey,
          apiKey,
          get().snapshot,
        );
        writeCache(cacheKey(eventKey), snapshot);
        if (live) set({ status: "ready", snapshot });
      } catch (error) {
        console.warn("TBA refresh failed", error);
        if (live) {
          set({
            ...get(),
            status: get().status === "ready" ? "ready" : "failed",
          });
        }
      } finally {
        running = false;
      }
    };
    void refresh();
    const again = () => void refresh();
    window.addEventListener("online", again);
    const timer = setInterval(again, refreshMs);
    const unregister = registerRefresh(refresh);
    return () => {
      live = false;
      unregister();
      window.removeEventListener("online", again);
      clearInterval(timer);
    };
  });
}

const fromSchedule = (m: ScheduledMatch): EventMatch => ({
  key: m.key,
  level: m.compLevel as CompLevel,
  red: m.red,
  blue: m.blue,
  redScore: null,
  blueScore: null,
  winner: null,
});

export interface TbaEvent {
  eventKey: string;
  status: TbaStatus;
  fetchedAt: string | null;
  teams: TbaEventSnapshot["teams"];
  rankings: TbaEventSnapshot["rankings"];
  matches: EventMatch[];
}

export function useTbaEvent(): TbaEvent {
  const { eventKey, schedule } = useScoutData();
  const training = useTrainingView();
  const store =
    eventKey === "" || training
      ? null
      : storeFor(`tba:${eventKey}`, () => eventStore(eventKey));
  const { status, snapshot } = useStore(store, idle);
  const matches = useMemo(
    () =>
      snapshot && snapshot.matches.length > 0
        ? snapshot.matches
        : schedule
            .map(fromSchedule)
            .sort((a, b) => matchOrder(a.key) - matchOrder(b.key)),
    [snapshot, schedule],
  );
  if (training) {
    return {
      eventKey,
      status: "ready",
      fetchedAt: training.startedAt,
      teams: training.teams,
      rankings: training.rankings,
      matches: training.matches,
    };
  }
  return {
    eventKey,
    status,
    fetchedAt: snapshot?.fetchedAt ?? null,
    teams: snapshot?.teams ?? [],
    rankings: snapshot?.rankings ?? [],
    matches,
  };
}
