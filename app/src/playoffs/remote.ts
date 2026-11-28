import { doc, onSnapshot } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import { createStore, storeFor, useStore } from "../data/store";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import type { PlayoffBoard } from "./board";
import { boardDoc, boardPath, parseShared, type Shared } from "./shared";

export interface RemoteState {
  shared: Shared | null;
  ready: boolean;
  failed: boolean;
  fromCache: boolean;
}

const idle: RemoteState = {
  shared: null,
  ready: false,
  failed: false,
  fromCache: false,
};

const makeStore = (eventKey: string) =>
  createStore<RemoteState>(idle, (set, get) =>
    onSnapshot(
      doc(db, "playoffBoards", eventKey),
      { includeMetadataChanges: true },
      (snap) =>
        set({
          shared: snap.exists() ? parseShared(snap.data()) : null,
          ready: true,
          failed: false,
          fromCache: snap.metadata.fromCache,
        }),
      (error) => {
        console.warn("Could not read playoffBoards", error);
        set({ ...get(), ready: true, failed: true });
      },
    ),
  );

export function useRemoteBoard(eventKey: string): RemoteState {
  const signedIn = useAuth().status === "signed-in" && eventKey !== "";
  const store = signedIn
    ? storeFor(`playoffBoards.${eventKey}`, () => makeStore(eventKey))
    : null;
  return useStore(store, idle);
}

export function sendBoard(
  eventKey: string,
  board: PlayoffBoard,
  ms: number,
  by: string,
): Promise<string> {
  return enqueueWrite(
    boardPath(eventKey),
    boardDoc(eventKey, board, ms, by),
    "Playoff board",
  );
}
