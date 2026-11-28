import type { PhotoItem } from "./state";

export interface PhotoStore {
  load(): Promise<PhotoItem[]>;
  put(item: PhotoItem): Promise<void>;
  remove(id: string): Promise<void>;
}

const dbName = "spectrum-photos";
const storeName = "items";

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);
    request.onupgradeneeded = () =>
      request.result.createObjectStore(storeName, { keyPath: "id" });
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function run<T>(
  mode: IDBTransactionMode,
  act: (store: IDBObjectStore) => IDBRequest<T>,
): Promise<T> {
  const db = await openDb();
  try {
    return await new Promise<T>((resolve, reject) => {
      const tx = db.transaction(storeName, mode);
      const request = act(tx.objectStore(storeName));
      tx.oncomplete = () => resolve(request.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}

export const idbStore: PhotoStore = {
  load: () => run("readonly", (s) => s.getAll() as IDBRequest<PhotoItem[]>),
  put: async (item) => {
    await run("readwrite", (s) => s.put(item));
  },
  remove: async (id) => {
    await run("readwrite", (s) => s.delete(id));
  },
};

export function memoryStore(): PhotoStore {
  const items = new Map<string, PhotoItem>();
  return {
    load: async () => [...items.values()],
    put: async (item) => {
      items.set(item.id, item);
    },
    remove: async (id) => {
      items.delete(id);
    },
  };
}
