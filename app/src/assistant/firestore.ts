import { deleteDoc, doc, onSnapshot, setDoc } from "firebase/firestore";
import { db } from "../firebase/client";
import type { RequestDoc } from "./queue";

export interface AssistantApi {
  watchSummary(
    docId: string,
    onData: (data: Record<string, unknown> | null) => void,
  ): () => void;
  post(docId: string, request: RequestDoc): Promise<void>;
  remove(docId: string): Promise<void>;
}

export const firestoreApi: AssistantApi = {
  watchSummary: (docId, onData) =>
    onSnapshot(
      doc(db, "assistantSummaries", docId),
      (snap) => onData(snap.exists() ? snap.data() : null),
      () => onData(null),
    ),
  post: (docId, request) =>
    setDoc(doc(db, "assistantRequests", docId), request),
  remove: (docId) => deleteDoc(doc(db, "assistantRequests", docId)),
};
