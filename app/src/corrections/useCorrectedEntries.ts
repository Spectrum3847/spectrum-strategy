import { useMemo } from "react";
import { useEventEntries } from "../data/entries";
import type { EventEntry } from "../data/parse";
import type { Feed } from "../data/store";
import { useCorrections } from "../data/useCorrections";
import { applyCorrections, type Corrected } from "./apply";

export interface CorrectedFeed extends Feed<Corrected<EventEntry>> {
  correctionsFailed: boolean;
}

export function useCorrectedEntries(eventKey: string): CorrectedFeed {
  const entries = useEventEntries(eventKey);
  const corrections = useCorrections(eventKey);
  const items = useMemo(
    () => applyCorrections(entries.items, corrections.items),
    [entries.items, corrections.items],
  );
  return {
    items,
    ready: entries.ready,
    failed: entries.failed,
    correctionsFailed: corrections.failed,
  };
}
