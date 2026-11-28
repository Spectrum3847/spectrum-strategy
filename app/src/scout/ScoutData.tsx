import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import bundled from "../../../assets/scout_config_default.json";
import { useAuth } from "../auth/AuthProvider";
import { useEventEntries } from "../data/entries";
import { teamKey } from "../data/tbaKey";
import { useTrainingScoutData } from "../training/view";
import { parseConfig, pickConfig, type ScoutConfig } from "./config";
import {
  applyTrades,
  parseShifts,
  parseTrades,
  type ScoutShifts,
  type ShiftTrade,
} from "./credit";
import { configCache, eventKeyStore, scheduleCache } from "./local";
import {
  watchActiveEvent,
  watchScoutConfig,
  watchScoutShifts,
  watchShiftTrades,
} from "./remote";
import type { RemoteEntry, ScheduledMatch } from "./schedule";
import { fetchEventMatches } from "./tba";

export type ScheduleStatus = "none" | "loading" | "ready" | "failed";

export interface ScoutData {
  config: ScoutConfig;
  eventKey: string;
  eventReady: boolean;
  setEventKey(key: string): void;
  schedule: ScheduledMatch[];
  scheduleFetchedAt: string | null;
  scheduleStatus: ScheduleStatus;
  refreshSchedule(): Promise<void>;
  entries: RemoteEntry[];
  shifts: ScoutShifts | null;
}

const Ctx = createContext<ScoutData | null>(null);

function startingConfig(): ScoutConfig {
  let active = parseConfig(bundled);
  const cached = configCache.get();
  if (cached) {
    try {
      active = pickConfig(active, parseConfig(cached));
    } catch {
    }
  }
  return active;
}

export function ScoutDataProvider({ children }: { children: ReactNode }) {
  const auth = useAuth();
  const signedIn = auth.status === "signed-in";
  const [config, setConfig] = useState(startingConfig);
  const [eventKey, setEventKeyState] = useState(eventKeyStore.get);
  const [activeEventReady, setActiveEventReady] = useState(false);
  const [schedule, setSchedule] = useState<ScheduledMatch[]>([]);
  const [fetchedAt, setFetchedAt] = useState<string | null>(null);
  const [status, setStatus] = useState<ScheduleStatus>("none");
  const entries = useEventEntries(eventKey).items;
  const [grid, setGrid] = useState<ScoutShifts | null>(null);
  const [trades, setTrades] = useState<ShiftTrade[] | null>(null);
  const shifts = useMemo(
    () => (grid && trades ? applyTrades(grid, trades) : null),
    [grid, trades],
  );
  const eventRef = useRef(eventKey);
  eventRef.current = eventKey;

  useEffect(() => {
    if (!signedIn) return;
    return watchScoutConfig((json) => {
      try {
        const incoming = parseConfig(json);
        setConfig((active) => {
          const winner = pickConfig(active, incoming);
          if (winner === incoming) configCache.set(json);
          return winner;
        });
      } catch {
      }
    });
  }, [signedIn]);

  useEffect(() => {
    setGrid(null);
    setTrades(null);
    if (!signedIn || eventKey === "") return;
    const stopGrid = watchScoutShifts(eventKey, (data) =>
      setGrid(parseShifts(data)),
    );
    const stopTrades = watchShiftTrades(eventKey, (docs) =>
      setTrades(parseTrades(docs)),
    );
    return () => {
      stopGrid();
      stopTrades();
    };
  }, [signedIn, eventKey]);

  const setEventKey = useCallback((key: string) => {
    const trimmed = key.trim();
    eventKeyStore.set(trimmed);
    setEventKeyState(trimmed);
  }, []);

  useEffect(() => {
    if (!signedIn) return;
    return watchActiveEvent((key) => {
      if (key !== null && key !== eventRef.current) setEventKey(key);
      setActiveEventReady(true);
    });
  }, [signedIn, setEventKey]);

  const inFlight = useRef<string | null>(null);
  const refreshSchedule = useCallback(async () => {
    const event = eventRef.current;
    if (event === "" || inFlight.current === event) return;
    inFlight.current = event;
    setStatus((s) => (s === "ready" ? s : "loading"));
    try {
      const apiKey = await teamKey();
      if (!apiKey) throw new Error("No TBA key available");
      const matches = await fetchEventMatches(event, apiKey);
      if (event !== eventRef.current) return;
      const at = new Date().toISOString();
      scheduleCache.set(event, { fetchedAt: at, matches });
      setSchedule(matches);
      setFetchedAt(at);
      setStatus("ready");
    } catch {
      if (event !== eventRef.current) return;
      setStatus((s) => (s === "ready" ? s : "failed"));
    } finally {
      if (inFlight.current === event) inFlight.current = null;
    }
  }, []);

  useEffect(() => {
    const cached = eventKey === "" ? null : scheduleCache.get(eventKey);
    setSchedule(cached?.matches ?? []);
    setFetchedAt(cached?.fetchedAt ?? null);
    setStatus(cached ? "ready" : "none");
    if (eventKey === "") return;
    void refreshSchedule();
    const again = () => void refreshSchedule();
    window.addEventListener("online", again);
    const timer = setInterval(again, 5 * 60_000);
    return () => {
      window.removeEventListener("online", again);
      clearInterval(timer);
    };
  }, [eventKey, refreshSchedule]);

  const value = useMemo(
    () => ({
      config,
      eventKey,
      eventReady:
        eventKey !== "" || activeEventReady || auth.status === "signed-out",
      setEventKey,
      schedule,
      scheduleFetchedAt: fetchedAt,
      scheduleStatus: status,
      refreshSchedule,
      entries,
      shifts,
    }),
    [
      config,
      eventKey,
      activeEventReady,
      auth.status,
      setEventKey,
      schedule,
      fetchedAt,
      status,
      refreshSchedule,
      entries,
      shifts,
    ],
  );
  return <Ctx value={value}>{children}</Ctx>;
}

export function useScoutData(): ScoutData {
  const data = useTrainingScoutData(useContext(Ctx));
  if (!data) throw new Error("useScoutData needs a ScoutDataProvider");
  return data;
}
