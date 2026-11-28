export interface LocalRecord {
  doc: Record<string, unknown>;
  queuedMs: number;
}

const dbName = "spectrum-board";
const storeName = "boards";
const fallbackPrefix = "ss.board.";

export const boardKey = (eventKey: string, matchNumber: number) =>
  `${eventKey}|${matchNumber}`;

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(dbName, 1);
    request.onupgradeneeded = () => request.result.createObjectStore(storeName);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

async function idbGet(key: string): Promise<LocalRecord | null> {
  const db = await openDb();
  try {
    return await new Promise((resolve, reject) => {
      const request = db.transaction(storeName).objectStore(storeName).get(key);
      request.onsuccess = () =>
        resolve((request.result as LocalRecord | undefined) ?? null);
      request.onerror = () => reject(request.error);
    });
  } finally {
    db.close();
  }
}

async function idbPut(key: string, record: LocalRecord): Promise<void> {
  const db = await openDb();
  try {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(storeName, "readwrite");
      tx.objectStore(storeName).put(record, key);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}

function lsGet(key: string): LocalRecord | null {
  try {
    const raw = localStorage.getItem(fallbackPrefix + key);
    return raw ? (JSON.parse(raw) as LocalRecord) : null;
  } catch {
    return null;
  }
}

export async function loadLocal(key: string): Promise<LocalRecord | null> {
  try {
    const found = await idbGet(key);
    if (found) return found;
  } catch {
  }
  return lsGet(key);
}

export async function saveLocal(
  key: string,
  record: LocalRecord,
): Promise<void> {
  try {
    await idbPut(key, record);
  } catch {
    localStorage.setItem(fallbackPrefix + key, JSON.stringify(record));
  }
}

export interface LocalBoard {
  key: string;
  record: LocalRecord;
}

export async function listLocal(): Promise<LocalBoard[]> {
  const found = new Map<string, LocalRecord>();
  try {
    const db = await openDb();
    try {
      await new Promise<void>((resolve, reject) => {
        const request = db
          .transaction(storeName)
          .objectStore(storeName)
          .openCursor();
        request.onsuccess = () => {
          const cursor = request.result;
          if (!cursor) {
            resolve();
            return;
          }
          found.set(String(cursor.key), cursor.value as LocalRecord);
          cursor.continue();
        };
        request.onerror = () => reject(request.error);
      });
    } finally {
      db.close();
    }
  } catch {
  }
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const name = localStorage.key(i);
      if (!name?.startsWith(fallbackPrefix)) continue;
      const key = name.slice(fallbackPrefix.length);
      const record = lsGet(key);
      if (record && !found.has(key)) found.set(key, record);
    }
  } catch {
  }
  return [...found].map(([key, record]) => ({ key, record }));
}

export async function deleteLocal(key: string): Promise<void> {
  try {
    const db = await openDb();
    try {
      await new Promise<void>((resolve, reject) => {
        const tx = db.transaction(storeName, "readwrite");
        tx.objectStore(storeName).delete(key);
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } finally {
      db.close();
    }
  } catch {
  }
  try {
    localStorage.removeItem(fallbackPrefix + key);
  } catch {
  }
}

export const idKey = (id: string) => `id|${id}`;
