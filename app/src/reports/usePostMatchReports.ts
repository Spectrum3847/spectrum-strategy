import { collection, onSnapshot } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import {
  type Feed,
  feedStore,
  idleFeed,
  storeFor,
  useStore,
} from "../data/store";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import {
  type Author,
  applySections,
  type PostMatchReport,
  parseReport,
  reportDoc,
  type Sections,
} from "./postMatch";

const watchReports = (
  onItems: (items: PostMatchReport[]) => void,
  onError: () => void,
) =>
  onSnapshot(
    collection(db, "postMatchReports"),
    (snap) => onItems(snap.docs.map((d) => parseReport(d.id, d.data()))),
    (error) => {
      console.warn("Could not read postMatchReports", error);
      onError();
    },
  );

export function usePostMatchReports(): Feed<PostMatchReport> {
  const signedIn = useAuth().status === "signed-in";
  const store = signedIn
    ? storeFor("postMatchReports", () =>
        feedStore<PostMatchReport>(watchReports),
      )
    : null;
  return useStore(store, idleFeed);
}

export const reportPath = (id: string) => `postMatchReports/${id}`;

export function savePostMatchReport(
  prev: PostMatchReport,
  sections: Sections,
  author: Author,
  label: string,
): Promise<string> {
  const next = applySections(prev, sections, author, Date.now());
  return enqueueWrite(reportPath(next.id), reportDoc(next), label);
}
