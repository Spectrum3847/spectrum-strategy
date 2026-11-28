import {
  type DocumentData,
  onSnapshot,
  type Query,
  type QuerySnapshot,
} from "firebase/firestore";
import { useSyncExternalStore } from "react";

export type SyncSource = "entries" | "pit" | "picks";

export interface SyncNote {
  open: boolean;
  fromCache: boolean;
  lastServerMs: number | null;
  failed: boolean;
}

type Notes = Partial<Record<SyncSource, SyncNote>>;

let notes: Notes = {};
const listeners = new Set<() => void>();

function set(source: SyncSource, next: Partial<SyncNote>) {
  const before = notes[source] ?? {
    open: true,
    fromCache: true,
    lastServerMs: null,
    failed: false,
  };
  notes = { ...notes, [source]: { ...before, ...next } };
  for (const notify of listeners) notify();
}

export function noteSnapshot(
  source: SyncSource,
  fromCache: boolean,
  now = Date.now(),
) {
  const before = notes[source];
  const wasLive = before !== undefined && !before.fromCache && !before.failed;
  set(source, {
    open: true,
    fromCache,
    failed: false,
    ...(!fromCache || wasLive ? { lastServerMs: now } : {}),
  });
}

export function noteFailed(source: SyncSource) {
  set(source, { failed: true });
}

export function noteClosed(source: SyncSource) {
  if (notes[source]) set(source, { open: false });
}

export const syncNotes = () => notes;

export function subscribeSync(notify: () => void) {
  listeners.add(notify);
  return () => listeners.delete(notify);
}

export const useSyncNotes = (): Notes =>
  useSyncExternalStore(subscribeSync, syncNotes, syncNotes);

export function watchTracked(
  source: SyncSource,
  target: Query<DocumentData>,
  onSnap: (snap: QuerySnapshot<DocumentData>) => void,
  onError: (error: unknown) => void,
): () => void {
  let first = true;
  const stop = onSnapshot(
    target,
    { includeMetadataChanges: true },
    (snap) => {
      noteSnapshot(source, snap.metadata.fromCache);
      if (!first && snap.docChanges().length === 0) return;
      first = false;
      onSnap(snap);
    },
    (error) => {
      noteFailed(source);
      onError(error);
    },
  );
  return () => {
    stop();
    noteClosed(source);
  };
}
