import { readCache, writeCache } from "../data/cache";
import { createStore, storeFor, useStore } from "../data/store";
import { teamKey } from "../data/tbaKey";
import { tbaGet } from "../scout/tba";

export interface EventKind {
  type: number | null;
  name: string;
}

const none: EventKind = { type: null, name: "" };
const cacheKey = (event: string) => `ss.eventType.${event}`;

export function parseEventKind(raw: unknown): EventKind {
  const r = (raw ?? {}) as {
    event_type?: unknown;
    event_type_string?: unknown;
  };
  return {
    type: typeof r.event_type === "number" ? r.event_type : null,
    name: typeof r.event_type_string === "string" ? r.event_type_string : "",
  };
}

export function useEventKind(eventKey: string): EventKind {
  const store =
    eventKey === ""
      ? null
      : storeFor(`eventKind:${eventKey}`, () =>
          createStore<EventKind>(
            readCache<EventKind>(cacheKey(eventKey)) ?? none,
            (set, get) => {
              let live = true;
              if (get().type === null) {
                void (async () => {
                  try {
                    const key = await teamKey();
                    if (!key) return;
                    const kind = parseEventKind(
                      await tbaGet(
                        `/event/${encodeURIComponent(eventKey)}/simple`,
                        key,
                      ),
                    );
                    writeCache(cacheKey(eventKey), kind);
                    if (live) set(kind);
                  } catch {
                  }
                })();
              }
              return () => {
                live = false;
              };
            },
          ),
        );
  return useStore(store, none);
}
