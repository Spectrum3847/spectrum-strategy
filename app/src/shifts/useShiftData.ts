import { useCallback, useEffect, useRef, useState } from "react";
import type { OutboxItem } from "../outbox/outbox";
import {
  parseShifts,
  parseTradeDocs,
  type ScoutShifts,
  type ShiftTradeDoc,
} from "../scout/credit";
import { schedulePath } from "./paths";
import { watchSchedule, watchTrades } from "./remote";
import { saveSchedule } from "./write";

export type Load = "loading" | "ready" | "failed";

interface Remote<T> {
  load: Load;
  fromCache: boolean;
  value: T;
}

const idle = <T>(value: T): Remote<T> => ({
  load: "loading",
  fromCache: false,
  value,
});

export interface ShiftData {
  load: Load;
  fromCache: boolean;
  shifts: ScoutShifts | null;
  trades: ShiftTradeDoc[];
  tradesLoad: Load;
  save(next: ScoutShifts): Promise<void>;
}

export function useShiftData(
  eventKey: string,
  signedIn: boolean,
  outbox: OutboxItem[],
): ShiftData {
  const [grid, setGrid] = useState<Remote<ScoutShifts | null>>(idle(null));
  const [trades, setTrades] = useState<Remote<ShiftTradeDoc[]>>(idle([]));
  const [draft, setDraft] = useState<ScoutShifts | null>(null);
  const saving = useRef(0);

  useEffect(() => {
    setGrid(idle(null));
    setTrades(idle([]));
    setDraft(null);
    if (!signedIn || eventKey === "") return;
    const stopGrid = watchSchedule(
      eventKey,
      (seen) =>
        setGrid({
          load: "ready",
          fromCache: seen.fromCache,
          value: parseShifts(seen.value),
        }),
      () => setGrid((g) => ({ ...g, load: "failed" })),
    );
    const stopTrades = watchTrades(
      eventKey,
      (seen) =>
        setTrades({
          load: "ready",
          fromCache: seen.fromCache,
          value: parseTradeDocs(seen.value),
        }),
      () => setTrades((t) => ({ ...t, load: "failed" })),
    );
    return () => {
      stopGrid();
      stopTrades();
    };
  }, [eventKey, signedIn]);

  useEffect(() => {
    const waiting = outbox.some(
      (i) =>
        i.path === schedulePath(eventKey) &&
        (i.status === "on-device" || i.status === "sending"),
    );
    if (!waiting && saving.current === 0) setDraft(null);
  }, [outbox, eventKey]);

  const save = useCallback(
    async (next: ScoutShifts) => {
      setDraft(next);
      saving.current += 1;
      try {
        await saveSchedule(next, eventKey);
      } catch (error) {
        setDraft(null);
        throw error;
      } finally {
        saving.current -= 1;
      }
    },
    [eventKey],
  );

  return {
    load: grid.load,
    fromCache: grid.fromCache,
    shifts: draft ?? grid.value,
    trades: trades.value,
    tradesLoad: trades.load,
    save,
  };
}
