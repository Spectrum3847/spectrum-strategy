import { collection, onSnapshot } from "firebase/firestore";
import { createStore, storeFor, useStore } from "../data/store";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import { type ProfileWrite, profilePath } from "./edits";
import {
  byDisplayName,
  type ManagedProfile,
  type ProfilesSeen,
  parseManaged,
} from "./profiles";

interface Snapshot extends ProfilesSeen {
  items: ManagedProfile[];
}

const idle: Snapshot = {
  items: [],
  ready: false,
  failed: false,
  code: null,
  fromCache: false,
  count: 0,
};

const makeStore = () =>
  createStore<Snapshot>(idle, (set) =>
    onSnapshot(
      collection(db, "userProfiles"),
      { includeMetadataChanges: true },
      (snap) => {
        const items = snap.docs
          .map((d) => parseManaged(d.id, d.data()))
          .sort(byDisplayName);
        set({
          items,
          ready: true,
          failed: false,
          code: null,
          fromCache: snap.metadata.fromCache,
          count: items.length,
        });
      },
      (error) =>
        set({ ...idle, ready: true, failed: true, code: error.code ?? null }),
    ),
  );

export function useProfiles(attempt: number): Snapshot {
  return useStore(storeFor(`userProfiles:${attempt}`, makeStore), idle);
}

export async function saveProfileWrites(writes: ProfileWrite[]) {
  for (const w of writes) {
    await enqueueWrite(profilePath(w.uid), w.doc, w.label);
  }
}
