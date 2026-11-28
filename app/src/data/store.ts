import { useSyncExternalStore } from "react";

type Stop = () => void;

export interface Store<S> {
  get(): S;
  subscribe(notify: () => void): Stop;
}

export function createStore<S>(
  initial: S,
  start: (set: (next: S) => void, get: () => S) => Stop,
): Store<S> {
  let state = initial;
  let stop: Stop | null = null;
  const listeners = new Set<() => void>();
  const set = (next: S) => {
    state = next;
    for (const notify of listeners) notify();
  };
  const get = () => state;
  return {
    get,
    subscribe(notify) {
      listeners.add(notify);
      if (!stop) stop = start(set, get);
      return () => {
        listeners.delete(notify);
        if (listeners.size === 0 && stop) {
          stop();
          stop = null;
        }
      };
    },
  };
}

const stores = new Map<string, Store<unknown>>();

export function storeFor<S>(key: string, make: () => Store<S>): Store<S> {
  let store = stores.get(key);
  if (!store) {
    store = make() as Store<unknown>;
    stores.set(key, store);
  }
  return store as Store<S>;
}

const never = () => () => undefined;

export function useStore<S>(store: Store<S> | null, idle: S): S {
  return useSyncExternalStore(
    store ? store.subscribe : never,
    store ? store.get : () => idle,
    () => idle,
  );
}

export interface Feed<T> {
  items: T[];
  ready: boolean;
  failed: boolean;
}

export const idleFeed: Feed<never> = { items: [], ready: false, failed: false };

export function feedStore<T>(
  watch: (onItems: (items: T[]) => void, onError: () => void) => Stop,
): Store<Feed<T>> {
  return createStore<Feed<T>>(idleFeed, (set, get) =>
    watch(
      (items) => set({ items, ready: true, failed: false }),
      () => set({ ...get(), ready: true, failed: true }),
    ),
  );
}
