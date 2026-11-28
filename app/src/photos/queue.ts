import {
  due,
  isStale,
  newItem,
  type Outcome,
  type PhotoItem,
  retried,
  settle,
  waitingEntry,
} from "./state";
import type { PhotoStore } from "./store";

export interface QueueDeps {
  store: PhotoStore;
  upload(blob: Blob): Promise<Outcome>;
  deleteRemote(key: string): Promise<boolean>;
  attach(entryId: string, keys: string[]): Promise<string[]>;
  now(): number;
}

export function createQueue(deps: QueueDeps) {
  let items: PhotoItem[] = [];
  let started: Promise<void> | undefined;
  let chain: Promise<void> = Promise.resolve();
  const listeners = new Set<() => void>();

  function commit(next: PhotoItem[]) {
    items = next;
    for (const notify of listeners) notify();
  }

  function save(item: PhotoItem) {
    deps.store.put(item).catch((error: unknown) => {
      console.error("Photo could not be stored", error);
    });
  }

  function patch(id: string, change: (item: PhotoItem) => PhotoItem) {
    const found = items.find((i) => i.id === id);
    if (!found) return undefined;
    const next = change(found);
    commit(items.map((i) => (i.id === id ? next : i)));
    save(next);
    return next;
  }

  function drop(id: string) {
    commit(items.filter((i) => i.id !== id));
    deps.store.remove(id).catch(() => undefined);
  }

  function start(): Promise<void> {
    started ??= (async () => {
      try {
        const saved = await deps.store.load();
        const loaded = saved.map(
          (i): PhotoItem =>
            i.state === "uploading" ? { ...i, state: "waiting" } : i,
        );
        const known = new Set(items.map((i) => i.id));
        commit([...loaded.filter((i) => !known.has(i.id)), ...items]);
      } catch (error) {
        console.error("Photo queue could not be read", error);
      }
    })();
    return started;
  }

  async function uploadOne(id: string) {
    const item = patch(id, (i) => ({ ...i, state: "uploading" }));
    if (!item) return;
    let outcome: Outcome;
    try {
      outcome = await deps.upload(item.blob);
    } catch {
      outcome = { type: "network" };
    }
    patch(id, (i) => settle(i, outcome, deps.now()));
  }

  async function attachAll() {
    const byEntry = new Map<string, PhotoItem[]>();
    for (const item of items) {
      if (item.state !== "uploaded" || !item.key) continue;
      if (item.entryId === waitingEntry) continue;
      byEntry.set(item.entryId, [...(byEntry.get(item.entryId) ?? []), item]);
    }
    for (const [entryId, group] of byEntry) {
      let on: string[] = [];
      try {
        on = await deps.attach(
          entryId,
          group.flatMap((i) => (i.key ? [i.key] : [])),
        );
      } catch {
      }
      for (const item of group) {
        if (item.key && on.includes(item.key)) {
          patch(item.id, (i) =>
            i.state === "uploaded" ? { ...i, state: "attached" } : i,
          );
        }
      }
    }
  }

  async function sweep() {
    for (const item of items.filter((i) => isStale(i, deps.now()))) {
      if (item.state === "uploaded" && item.key)
        void deps.deleteRemote(item.key);
      drop(item.id);
    }
  }

  async function run() {
    await start();
    for (const item of items.filter((i) => due(i, deps.now()))) {
      await uploadOne(item.id);
    }
    await attachAll();
    await sweep();
  }

  function pass(): Promise<void> {
    chain = chain.then(run, run).catch((error: unknown) => {
      console.error("Photo pass failed", error);
    });
    return chain;
  }

  function after(work: () => Promise<void> | void): Promise<void> {
    chain = chain.then(work, work).catch(() => undefined);
    return chain;
  }

  return {
    items: () => items,
    subscribe(notify: () => void) {
      listeners.add(notify);
      return () => {
        listeners.delete(notify);
      };
    },
    start,
    pass,

    async add(
      entryId: string,
      team: number,
      blob: Blob,
      eventKey?: string,
    ): Promise<PhotoItem> {
      await start();
      const item = newItem(
        crypto.randomUUID(),
        entryId,
        team,
        blob,
        new Date(deps.now()),
        eventKey,
      );
      commit([...items, item]);
      await deps.store.put(item).catch((error: unknown) => {
        console.error("Photo could not be stored", error);
      });
      void pass();
      return item;
    },

    retry(id: string) {
      patch(id, retried);
      void pass();
    },

    place(moves: ReadonlyMap<string, string>) {
      let moved = false;
      for (const [id, entryId] of moves) {
        const item = items.find((i) => i.id === id);
        if (item?.entryId !== waitingEntry) continue;
        patch(id, (i) => ({ ...i, entryId }));
        moved = true;
      }
      if (moved) void pass();
    },

    discard(id: string): Promise<void> {
      return after(() => {
        const item = items.find((i) => i.id === id);
        if (!item) return;
        if (item.key && item.state !== "attached")
          void deps.deleteRemote(item.key);
        drop(id);
      });
    },

    release(keys: readonly string[]): Promise<void> {
      return after(async () => {
        for (const key of keys) {
          for (const item of items.filter((i) => i.key === key)) drop(item.id);
          await deps.deleteRemote(key);
        }
      });
    },
  };
}

export type PhotoQueue = ReturnType<typeof createQueue>;
