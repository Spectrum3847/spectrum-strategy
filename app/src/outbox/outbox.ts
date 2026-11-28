import { onAuthStateChanged } from "firebase/auth";
import {
  collection,
  type DocumentData,
  deleteDoc,
  doc,
  FieldPath,
  getDocs,
  onSnapshot,
  query,
  setDoc,
  Timestamp,
  where,
} from "firebase/firestore";
import { dataAuth, db } from "../firebase/client";
import { isTraining, TrainingWriteError } from "../training/session";
import {
  confirm,
  confirmDelete,
  type DocObservation,
  isLostDelete,
  isLostWrite,
  isRefusal,
  type OutboxStatus,
  resendDecision,
  sameDocument,
  shouldSend,
} from "./confirm";
import { sendOrder, supersede, type WriteKind } from "./order";
import { decodeData, encodeData, type Json } from "./serialize";
import { loadItems, saveItems } from "./store";

export interface OutboxItem {
  id: string;
  path: string;
  data: Json;
  kind?: WriteKind;
  label: string;
  createdAt: string;
  status: OutboxStatus;
  error?: string;
}

const resendIntervalMs = 15_000;
const proofPrefix = "proof-outbox-";

let items: OutboxItem[] = [];
let signedIn = false;
const subscribers = new Set<() => void>();
const watchers = new Map<string, () => void>();
let saveChain: Promise<void> = Promise.resolve();
let ready: Promise<void> | undefined;

function commit(next: OutboxItem[]): Promise<void> {
  items = next;
  for (const notify of subscribers) notify();
  const snapshot = next;
  const saved = saveChain
    .catch(() => undefined)
    .then(() => saveItems(snapshot));
  saveChain = saved;
  return saved.catch((error: unknown) => {
    console.error("Outbox save failed", error);
  });
}

function update(id: string, patch: (item: OutboxItem) => OutboxItem) {
  return commit(items.map((item) => (item.id === id ? patch(item) : item)));
}

function stopWatching(id: string) {
  watchers.get(id)?.();
  watchers.delete(id);
}

const queued = new Set<string>();

function write(item: OutboxItem): Promise<void> {
  const ref = doc(db, item.path);
  if (item.kind === "delete") return deleteDoc(ref);
  const data = decodeData(item.data) as DocumentData;
  if (item.kind !== "merge") return setDoc(ref, data);
  return setDoc(ref, data, {
    mergeFields: Object.keys(data).map((key) => new FieldPath(key)),
  });
}

function send(item: OutboxItem) {
  queued.add(item.id);
  write(item).then(
    () => {
      queued.delete(item.id);
      stopWatching(item.id);
      void update(item.id, (i) =>
        i.status === "refused" ? i : { ...i, status: "in-database" },
      );
    },
    (error: { code?: string; message: string }) => {
      queued.delete(item.id);
      if (!isRefusal(error.code)) return;
      stopWatching(item.id);
      void update(item.id, (i) =>
        i.status === "in-database"
          ? i
          : { ...i, status: "refused", error: error.message },
      );
    },
  );
}

function resend(id: string) {
  const item = items.find((i) => i.id === id);
  if (!item || resendDecision(item.status, signedIn) !== "resend") return;
  send(item);
}

function watch(item: OutboxItem) {
  if (watchers.has(item.id) || !signedIn) return;
  const unsubscribe = onSnapshot(
    doc(db, item.path),
    { includeMetadataChanges: true },
    (snapshot) => {
      const current = items.find((i) => i.id === item.id);
      if (!current) return;
      const seen: DocObservation = {
        exists: snapshot.exists(),
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
        fromCache: snapshot.metadata.fromCache,
        online: navigator.onLine,
        ...(current.kind !== "merge" &&
        current.kind !== "delete" &&
        snapshot.exists()
          ? { matches: sameDocument(encodeData(snapshot.data()), current.data) }
          : {}),
      };
      const deleting = current.kind === "delete";
      if (deleting ? isLostDelete(seen) : isLostWrite(seen)) {
        queued.delete(item.id);
        resend(item.id);
        return;
      }
      if (seen.hasPendingWrites) queued.add(item.id);
      const status = deleting
        ? confirmDelete(current.status, seen)
        : confirm(current.status, seen, current.kind !== "merge");
      if (status === current.status) return;
      void update(item.id, (i) => ({ ...i, status }));
      if (status === "in-database") {
        queued.delete(item.id);
        stopWatching(item.id);
      }
    },
    () => stopWatching(item.id),
  );
  watchers.set(item.id, unsubscribe);
}

function pass() {
  for (const item of sendOrder(items)) {
    if (resendDecision(item.status, signedIn) !== "resend") continue;
    watch(item);
    if (shouldSend(queued.has(item.id), navigator.onLine)) send(item);
  }
}

function stopAllWatching() {
  for (const id of [...watchers.keys()]) stopWatching(id);
}

export function resendNow() {
  pass();
}

export function getOutbox(): OutboxItem[] {
  return items;
}

export function isSignedIn(): boolean {
  return signedIn;
}

export function subscribeOutbox(notify: () => void): () => void {
  subscribers.add(notify);
  return () => subscribers.delete(notify);
}

export function startOutbox(): Promise<void> {
  ready ??= (async () => {
    items = await loadItems();
    for (const notify of subscribers) notify();
    onAuthStateChanged(dataAuth, (user) => {
      signedIn = user !== null;
      for (const notify of subscribers) notify();
      if (signedIn) pass();
      else stopAllWatching();
    });
    window.addEventListener("online", pass);
    window.addEventListener("focus", pass);
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") pass();
    });
    setInterval(() => {
      if (items.some((i) => resendDecision(i.status, signedIn) !== "none")) {
        pass();
      }
    }, resendIntervalMs);
  })();
  return ready;
}

export function dismissItem(id: string) {
  stopWatching(id);
  void commit(items.filter((i) => i.id !== id));
}

export function dismissFinished() {
  for (const item of items) {
    if (item.status === "in-database") stopWatching(item.id);
  }
  void commit(items.filter((i) => i.status !== "in-database"));
}

async function enqueue(
  kind: WriteKind,
  path: string,
  data: DocumentData,
  label: string,
): Promise<string> {
  if (isTraining()) throw new TrainingWriteError();
  await startOutbox();
  const item: OutboxItem = {
    id: crypto.randomUUID(),
    path,
    data: encodeData(data),
    kind,
    label,
    createdAt: new Date().toISOString(),
    status: "on-device",
  };
  const { kept, dropped } = supersede(items, path, kind);
  for (const old of dropped) {
    queued.delete(old.id);
    stopWatching(old.id);
  }
  await commit([item, ...kept]);
  watch(item);
  if (signedIn) send(item);
  return item.id;
}

export function enqueueWrite(
  path: string,
  data: DocumentData,
  label: string,
): Promise<string> {
  return enqueue("set", path, data, label);
}

export function enqueueMerge(
  path: string,
  data: DocumentData,
  label: string,
): Promise<string> {
  return enqueue("merge", path, data, label);
}

export function enqueueDelete(path: string, label: string): Promise<string> {
  return enqueue("delete", path, {}, label);
}

export function enqueueProofEntry(
  uid: string,
  displayName: string,
): Promise<string> {
  const entryId = `${proofPrefix}${crypto.randomUUID().slice(0, 8)}`;
  const now = new Date().toISOString();
  return enqueueWrite(
    `scoutEntries/${entryId}`,
    {
      id: entryId,
      matchId: "zz-outbox-proof",
      teamNumber: 99999,
      alliance: "Red",
      notes: "Outbox proof write from the React app. Safe to delete.",
      authorUid: uid,
      authorDisplayName: displayName,
      updatedAt: now,
      createdAt: now,
      updatedAtTs: Timestamp.now(),
      byPhase: {},
    },
    entryId,
  );
}

export async function deleteProofEntries(uid: string): Promise<number> {
  const found = await getDocs(
    query(collection(db, "scoutEntries"), where("authorUid", "==", uid)),
  );
  const proofs = found.docs.filter((d) => d.id.startsWith(proofPrefix));
  await Promise.all(proofs.map((d) => deleteDoc(d.ref)));
  const gone = new Set(proofs.map((d) => `scoutEntries/${d.id}`));
  for (const item of items) if (gone.has(item.path)) stopWatching(item.id);
  await commit(items.filter((i) => !gone.has(i.path)));
  return proofs.length;
}
