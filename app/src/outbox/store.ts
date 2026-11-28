import type { OutboxItem } from "./outbox";

const dbName = "spectrum-outbox";
const storeName = "kv";
const itemsKey = "items";
const fallbackKey = "ss.outbox.v2";

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(storeName);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function idbGet(): Promise<OutboxItem[] | undefined> {
  const db = await openDb();
  try {
    return await new Promise((resolve, reject) => {
      const request = db
        .transaction(storeName)
        .objectStore(storeName)
        .get(itemsKey);
      request.onsuccess = () => resolve(request.result as OutboxItem[]);
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

async function idbPut(items: OutboxItem[]): Promise<void> {
  const db = await openDb();
  try {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(storeName, "readwrite");
      tx.objectStore(storeName).put(items, itemsKey);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}

function lsGet(): OutboxItem[] {
  try {
    const raw = localStorage.getItem(fallbackKey);
    return raw ? (JSON.parse(raw) as OutboxItem[]) : [];
  } catch {
    return [];
  }
}

function lsPut(items: OutboxItem[]) {
  try {
    localStorage.setItem(fallbackKey, JSON.stringify(items));
  } catch {
  }
}

export async function loadItems(): Promise<OutboxItem[]> {
  try {
    const items = await idbGet();
    if (items) return items;
  } catch {
  }
  return lsGet();
}

export async function saveItems(items: OutboxItem[]): Promise<void> {
  try {
    await idbPut(items);
  } catch {
    lsPut(items);
  }
}
