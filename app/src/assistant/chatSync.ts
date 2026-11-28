import {
  collection,
  deleteDoc,
  doc,
  limit,
  onSnapshot,
  query,
  where,
} from "firebase/firestore";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import { parseSession, type Session, sessionDoc } from "./chat";

export interface ChatApi {
  watchChats(
    uid: string,
    onData: (chats: Session[]) => void,
    onError: () => void,
  ): () => void;
  saveChat(session: Session, uid: string): Promise<string>;
  deleteChat(id: string): Promise<void>;
}

export const chatApi: ChatApi = {
  watchChats: (uid, onData, onError) =>
    onSnapshot(
      query(
        collection(db, "assistantChats"),
        where("authorUid", "==", uid),
        limit(50),
      ),
      (snap) => onData(snap.docs.flatMap((d) => parseSession(d.data()) ?? [])),
      (error) => {
        console.warn("Could not read assistantChats", error);
        onError();
      },
    ),
  saveChat: (session, uid) =>
    enqueueWrite(
      `assistantChats/${session.id}`,
      sessionDoc(session, uid, new Date()),
      "AI chat",
    ),
  deleteChat: (id) => deleteDoc(doc(db, "assistantChats", id)),
};
