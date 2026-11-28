import { onAuthStateChanged } from "firebase/auth";
import { doc, getDoc } from "firebase/firestore";
import { useMemo, useSyncExternalStore } from "react";
import { readCache, writeCache } from "../data/cache";
import { dataAuth, db } from "../firebase/client";
import { isTraining } from "../training/session";
import { attachKeys, detachKey } from "./attach";
import { createClient, type DownloadResult } from "./client";
import { workerOrigin } from "./keys";
import { createQueue } from "./queue";
import type { PhotoItem } from "./state";
import { idbStore } from "./store";

const mirrorKey = "ss.photo.worker";
let origin: string | null = null;

async function resolveOrigin(): Promise<string | null> {
  if (origin) return origin;
  try {
    const snap = await getDoc(doc(db, "appConfig", "apiKeys"));
    const found = workerOrigin(snap.data()?.photoWorker);
    if (found) {
      origin = found;
      writeCache(mirrorKey, found);
      return found;
    }
  } catch {
  }
  return workerOrigin(readCache<string>(mirrorKey));
}

async function idToken(): Promise<string | null> {
  try {
    return (await dataAuth.currentUser?.getIdToken()) ?? null;
  } catch {
    return null;
  }
}

const client = createClient({
  origin: resolveOrigin,
  token: idToken,
  online: () => navigator.onLine,
  fetch: (input, init) => fetch(input, init),
});

export const uploadPhoto = client.upload;

export const photoQueue = createQueue({
  store: idbStore,
  upload: async (blob) =>
    isTraining()
      ? { type: "unavailable", reason: "training" }
      : client.upload(blob),
  deleteRemote: client.remove,
  attach: attachKeys,
  now: () => Date.now(),
});

const passEveryMs = 30_000;
let started = false;

export function startPhotoQueue() {
  if (started) return;
  started = true;
  const pass = () => void photoQueue.pass();
  pass();
  onAuthStateChanged(dataAuth, (user) => {
    if (user) pass();
  });
  window.addEventListener("online", pass);
  window.addEventListener("focus", pass);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") pass();
  });
  setInterval(() => {
    if (photoQueue.items().some((i) => i.state !== "attached")) pass();
  }, passEveryMs);
}

export { detachKey };

export function useEntryItems(entryId: string): PhotoItem[] {
  const all = useSyncExternalStore(photoQueue.subscribe, photoQueue.items);
  return useMemo(
    () => all.filter((i) => i.entryId === entryId),
    [all, entryId],
  );
}

const fetched = new Map<string, Promise<DownloadResult>>();
const urls = new Map<string, string>();

export type PhotoFetch =
  | { type: "ok"; url: string }
  | Exclude<DownloadResult, { type: "ok" }>;

export async function fetchPhoto(key: string): Promise<PhotoFetch> {
  const known = urls.get(key);
  if (known) return { type: "ok", url: known };
  let pending = fetched.get(key);
  if (!pending) {
    pending = client.download(key);
    fetched.set(key, pending);
  }
  const result = await pending;
  if (result.type !== "ok") {
    fetched.delete(key);
    return result;
  }
  const url = urls.get(key) ?? URL.createObjectURL(result.blob);
  urls.set(key, url);
  return { type: "ok", url };
}
