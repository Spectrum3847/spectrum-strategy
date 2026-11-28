import { collection, onSnapshot, query, where } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import { type EventEntry, parseEventEntry } from "../data/parse";
import {
  type Feed,
  feedStore,
  idleFeed,
  storeFor,
  useStore,
} from "../data/store";
import { db } from "../firebase/client";

export function seasonOf(eventKey: string): string | null {
  return /^\d{4}/.exec(eventKey)?.[0] ?? null;
}

export const seasonQuery = (season: string) =>
  query(
    collection(db, "scoutEntries"),
    where("eventKey", ">=", season),
    where("eventKey", "<", String(Number(season) + 1)),
  );

export function useAllEntries(
  enabled: boolean,
  season: string | null,
): Feed<EventEntry> {
  const signedIn = useAuth().status === "signed-in";
  const store =
    enabled && signedIn && season !== null
      ? storeFor(`entries:season:${season}`, () =>
          feedStore<EventEntry>((on, fail) =>
            onSnapshot(
              seasonQuery(season),
              (snap) =>
                on(snap.docs.map((d) => parseEventEntry(d.id, d.data()))),
              (error) => {
                console.warn("Could not read the season's entries", error);
                fail();
              },
            ),
          ),
        )
      : null;
  return useStore(store, idleFeed);
}
