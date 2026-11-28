import { readCache, writeCache } from "../data/cache";
import { registerRefresh } from "../data/refresh";
import { createStore, type Store, storeFor, useStore } from "../data/store";
import { teamKey } from "../data/tbaKey";
import { type Forecast, fetchEpa, fetchForecasts } from "./outside";

export interface Outside<T> {
  status: "none" | "loading" | "ready" | "failed";
  data: T | null;
  fetchedAt?: string | null;
}

const refreshMs = 10 * 60_000;

function outsideStore<T>(
  cacheKey: string,
  load: () => Promise<T>,
): Store<Outside<T>> {
  const cached = readCache<T>(cacheKey);
  const stampKey = `${cacheKey}.at`;
  const initial: Outside<T> = cached
    ? { status: "ready", data: cached, fetchedAt: readCache<string>(stampKey) }
    : { status: "none", data: null };
  return createStore(initial, (set, get) => {
    let live = true;
    let running = false;
    const refresh = async () => {
      if (running) return;
      running = true;
      if (get().status !== "ready") set({ ...get(), status: "loading" });
      try {
        const data = await load();
        const fetchedAt = new Date().toISOString();
        writeCache(cacheKey, data);
        writeCache(stampKey, fetchedAt);
        if (live) set({ status: "ready", data, fetchedAt });
      } catch {
        if (live) {
          const ready = get().status === "ready";
          set({ ...get(), status: ready ? "ready" : "failed" });
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

const idle: Outside<never> = { status: "none", data: null };

export function useEpa(eventKey: string): Outside<Record<number, number>> {
  const store =
    eventKey === ""
      ? null
      : storeFor(`epa:${eventKey}`, () =>
          outsideStore(`ss.epa.${eventKey}`, () => fetchEpa(eventKey)),
        );
  return useStore(store, idle);
}

export function useForecasts(
  eventKey: string,
): Outside<Record<string, Forecast>> {
  const store =
    eventKey === ""
      ? null
      : storeFor(`forecasts:${eventKey}`, () =>
          outsideStore(`ss.forecasts.${eventKey}`, async () => {
            const apiKey = await teamKey();
            if (!apiKey) throw new Error("No TBA key available");
            return fetchForecasts(eventKey, apiKey);
          }),
        );
  return useStore(store, idle);
}
