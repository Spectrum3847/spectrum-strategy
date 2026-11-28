import { useMemo } from "react";
import { useAuth } from "../auth/AuthProvider";
import { watchEventEntries } from "../scout/remote";
import { useTrainingEntries } from "../training/entries";
import { useTrainingSession } from "../training/session";
import type { EventEntry } from "./parse";
import { type Feed, feedStore, idleFeed, storeFor, useStore } from "./store";

export function useEventEntries(eventKey: string): Feed<EventEntry> {
  const signedIn = useAuth().status === "signed-in";
  const training = useTrainingSession() !== null;
  const local = useTrainingEntries();
  const store =
    signedIn && eventKey !== "" && !training
      ? storeFor(`entries:${eventKey}`, () =>
          feedStore<EventEntry>((on, fail) =>
            watchEventEntries(eventKey, on, fail),
          ),
        )
      : null;
  const live = useStore(store, idleFeed);
  const trained = useMemo(
    () => ({ items: local.entries, ready: true, failed: false }),
    [local],
  );
  return training ? trained : live;
}
