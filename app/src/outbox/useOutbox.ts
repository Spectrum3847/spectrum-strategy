import { useSyncExternalStore } from "react";
import { getOutbox, subscribeOutbox } from "./outbox";

export function useOutbox() {
  return useSyncExternalStore(subscribeOutbox, getOutbox);
}
