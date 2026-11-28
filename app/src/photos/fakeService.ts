import { useMemo, useSyncExternalStore } from "react";
import { vi } from "vitest";
import type { Detached } from "./attach";
import { createQueue } from "./queue";
import type { PhotoFetch } from "./service";
import type { Outcome, PhotoItem } from "./state";
import { memoryStore } from "./store";

export const net = {
  upload: vi.fn<(blob: Blob) => Promise<Outcome>>(),
  remove: vi.fn<(key: string) => Promise<boolean>>(),
  attach: vi.fn<(entryId: string, keys: string[]) => Promise<string[]>>(),
  detach: vi.fn<(entryId: string, key: string) => Promise<Detached>>(),
  fetchPhoto: vi.fn<(key: string) => Promise<PhotoFetch>>(),
};

export function resetNet() {
  net.upload.mockReset();
  net.upload.mockResolvedValue({
    type: "response",
    status: 201,
    key: "new-key.jpg",
  });
  net.remove.mockReset();
  net.remove.mockResolvedValue(true);
  net.attach.mockReset();
  net.attach.mockResolvedValue([]);
  net.detach.mockReset();
  net.detach.mockResolvedValue("queued");
  net.fetchPhoto.mockReset();
  net.fetchPhoto.mockImplementation(async (key) => ({
    type: "ok",
    url: `blob:${key}`,
  }));
}
resetNet();

export const photoQueue = createQueue({
  store: memoryStore(),
  upload: (blob) => net.upload(blob),
  deleteRemote: (key) => net.remove(key),
  attach: (entryId, keys) => net.attach(entryId, keys),
  now: () => Date.now(),
});

export async function resetQueue() {
  for (const item of photoQueue.items()) await photoQueue.discard(item.id);
  resetNet();
}

export function useEntryItems(entryId: string): PhotoItem[] {
  const all = useSyncExternalStore(photoQueue.subscribe, photoQueue.items);
  return useMemo(
    () => all.filter((i) => i.entryId === entryId),
    [all, entryId],
  );
}

export const detachKey = (entryId: string, key: string) =>
  net.detach(entryId, key);
export const fetchPhoto = (key: string) => net.fetchPhoto(key);
export const startPhotoQueue = () => undefined;
