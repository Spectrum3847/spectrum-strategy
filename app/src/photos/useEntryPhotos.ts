import { useMemo, useState } from "react";
import { entryPath } from "../forms/delivery";
import { getOutbox, subscribeOutbox } from "../outbox/outbox";
import { whenInDatabase } from "../outbox/settled";
import { preparePhoto } from "./compress";
import { maxPhotos } from "./resize";
import { detachKey, photoQueue, useEntryItems } from "./service";
import { buildSlots, canAdd, type Slot, waitingEntry } from "./state";

export interface PhotoTarget {
  entryId: string | null;
  team: number;
  eventKey: string;
}

export interface EntryPhotos {
  slots: Slot[];
  canAdd: boolean;
  waiting: boolean;
  busy: boolean;
  notice: string | null;
  add(files: File[]): Promise<void>;
  remove(slot: Slot): void;
  retry(id: string): void;
}

const none: ReadonlySet<string> = new Set();

export function useEntryPhotos(
  target: PhotoTarget,
  existingKeys: readonly string[],
): EntryPhotos {
  const { entryId, team, eventKey } = target;
  const queueId = entryId ?? waitingEntry;
  const queued = useEntryItems(queueId);
  const items = useMemo(
    () =>
      entryId === null
        ? queued.filter((i) => i.team === team && i.eventKey === eventKey)
        : queued,
    [queued, entryId, team, eventKey],
  );
  const [removed, setRemoved] = useState<ReadonlySet<string>>(none);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const slots = useMemo(
    () => buildSlots(existingKeys, removed, items),
    [existingKeys, removed, items],
  );

  async function add(files: File[]) {
    setNotice(null);
    let count = slots.length;
    let skipped = 0;
    let unreadable = 0;
    setBusy(true);
    try {
      for (const file of files) {
        if (count >= maxPhotos) {
          skipped++;
          continue;
        }
        try {
          await photoQueue.add(
            queueId,
            team,
            await preparePhoto(file),
            eventKey,
          );
          count++;
        } catch {
          unreadable++;
        }
      }
    } finally {
      setBusy(false);
    }
    const parts = [
      skipped > 0 && `Only ${maxPhotos} photos fit, ${skipped} not added.`,
      unreadable > 0 &&
        `${unreadable} could not be read or is too large to upload.`,
    ].filter(Boolean);
    setNotice(parts.length > 0 ? parts.join(" ") : null);
  }

  async function takeOff(slot: Slot, key: string) {
    if (entryId === null) return;
    let result: Awaited<ReturnType<typeof detachKey>> = "no-entry";
    try {
      result = await detachKey(entryId, key);
    } catch {
    }
    if (result === "no-entry") {
      setRemoved((r) => {
        const rest = new Set(r);
        rest.delete(slot.id);
        rest.delete(key);
        return rest;
      });
      setNotice("Could not remove the photo. Try again when online.");
      return;
    }
    if (result === "queued") {
      const stored = await whenInDatabase(
        entryPath("pit", entryId),
        getOutbox,
        subscribeOutbox,
      );
      if (!stored) return;
    }
    await photoQueue.release([key]);
  }

  function remove(slot: Slot) {
    setNotice(null);
    if (slot.item && slot.item.state !== "attached") {
      void photoQueue.discard(slot.item.id);
      return;
    }
    if (!slot.key) return;
    setRemoved(new Set([...removed, slot.id, slot.key]));
    void takeOff(slot, slot.key);
  }

  return {
    slots,
    canAdd: canAdd(slots),
    waiting: entryId === null,
    busy,
    notice,
    add,
    remove,
    retry: photoQueue.retry,
  };
}
