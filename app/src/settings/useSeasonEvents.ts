import { useEffect, useState } from "react";
import { readCache, writeCache } from "../data/cache";
import { teamKey } from "../data/tbaKey";
import { tbaGet } from "../scout/tba";
import { parseEvents, type SeasonEvent, seasonOf } from "./events";

const cacheKey = (year: number) => `ss.settings.events.${year}`;

export type EventsStatus = "loading" | "ready" | "failed";

export function useSeasonEvents(year: number) {
  const [state, setState] = useState<{
    status: EventsStatus;
    events: SeasonEvent[];
  }>(() => ({
    status: "loading",
    events: readCache<SeasonEvent[]>(cacheKey(year)) ?? [],
  }));

  useEffect(() => {
    let live = true;
    const saved = readCache<SeasonEvent[]>(cacheKey(year)) ?? [];
    setState({ status: "loading", events: saved });
    (async () => {
      try {
        const apiKey = await teamKey();
        if (!apiKey) throw new Error("No TBA key available");
        const events = parseEvents(
          await tbaGet(`/events/${year}/simple`, apiKey),
        );
        if (events.length > 0) writeCache(cacheKey(year), events);
        if (live) setState({ status: "ready", events });
      } catch (error) {
        console.warn("Could not load the season's events", error);
        if (live) setState({ status: "failed", events: saved });
      }
    })();
    return () => {
      live = false;
    };
  }, [year]);

  return state;
}

export function savedEventName(eventKey: string): string | null {
  const year = seasonOf(eventKey);
  if (year === null) return null;
  const events = readCache<SeasonEvent[]>(cacheKey(year));
  return events?.find((e) => e.key === eventKey)?.name ?? null;
}
