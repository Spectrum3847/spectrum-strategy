import { useEffect, useSyncExternalStore } from "react";
import { usePitEntries } from "../data/useCollections";
import { photoQueue } from "./service";
import { placements } from "./waiting";

export function usePlaceWaitingPhotos() {
  const feed = usePitEntries();
  const items = useSyncExternalStore(photoQueue.subscribe, photoQueue.items);
  useEffect(() => {
    if (!feed.ready) return;
    const moves = placements(items, feed.items);
    if (moves.size > 0) photoQueue.place(moves);
  }, [feed.ready, feed.items, items]);
}
