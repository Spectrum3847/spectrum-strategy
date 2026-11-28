import { collection, doc, onSnapshot, query, where } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import { createStore, storeFor, useStore } from "../data/store";
import { db } from "../firebase/client";
import { bundled } from "./field";
import { newest, parseSession, type Session } from "./model";

export interface RemoteBoard {
  board: Session | null;
  ready: boolean;
  failed: boolean;
  fromCache: boolean;
}

const idle: RemoteBoard = {
  board: null,
  ready: false,
  failed: false,
  fromCache: false,
};

function makeStore(eventKey: string, matchNumber: number) {
  return createStore<RemoteBoard>(idle, (set, get) =>
    onSnapshot(
      query(
        collection(db, "strategyBoards"),
        where("eventKey", "==", eventKey),
        where("matchNumber", "==", matchNumber),
      ),
      { includeMetadataChanges: true },
      (snap) =>
        set({
          board: newest(
            snap.docs.map((d) => parseSession(d.id, d.data(), bundled.latest)),
          ),
          ready: true,
          failed: false,
          fromCache: snap.metadata.fromCache,
        }),
      (error) => {
        console.warn("Could not read strategyBoards", error);
        set({ ...get(), ready: true, failed: true });
      },
    ),
  );
}

export function useRemoteBoard(
  eventKey: string,
  matchNumber: number,
): RemoteBoard {
  const signedIn = useAuth().status === "signed-in";
  const store =
    signedIn && eventKey !== ""
      ? storeFor(`strategyBoards.${eventKey}.${matchNumber}`, () =>
          makeStore(eventKey, matchNumber),
        )
      : null;
  return useStore(store, idle);
}

function idStore(id: string) {
  return createStore<RemoteBoard>(idle, (set, get) =>
    onSnapshot(
      doc(db, "strategyBoards", id),
      { includeMetadataChanges: true },
      (snap) =>
        set({
          board: snap.exists()
            ? parseSession(snap.id, snap.data(), bundled.latest)
            : null,
          ready: true,
          failed: false,
          fromCache: snap.metadata.fromCache,
        }),
      (error) => {
        console.warn("Could not read the strategy board", error);
        set({ ...get(), ready: true, failed: true });
      },
    ),
  );
}

export function useRemoteBoardById(id: string): RemoteBoard {
  const signedIn = useAuth().status === "signed-in";
  const store =
    signedIn && id !== ""
      ? storeFor(`strategyBoards.id.${id}`, () => idStore(id))
      : null;
  return useStore(store, idle);
}

export interface RemoteBoards {
  boards: Session[];
  ready: boolean;
  failed: boolean;
  fromCache: boolean;
}

const idleAll: RemoteBoards = {
  boards: [],
  ready: false,
  failed: false,
  fromCache: false,
};

function allStore() {
  return createStore<RemoteBoards>(idleAll, (set, get) =>
    onSnapshot(
      collection(db, "strategyBoards"),
      { includeMetadataChanges: true },
      (snap) =>
        set({
          boards: snap.docs.map((d) =>
            parseSession(d.id, d.data(), bundled.latest),
          ),
          ready: true,
          failed: false,
          fromCache: snap.metadata.fromCache,
        }),
      (error) => {
        console.warn("Could not read strategyBoards", error);
        set({ ...get(), ready: true, failed: true });
      },
    ),
  );
}

export function useRemoteBoards(): RemoteBoards {
  const signedIn = useAuth().status === "signed-in";
  const store = signedIn ? storeFor("strategyBoards.all", allStore) : null;
  return useStore(store, idleAll);
}
