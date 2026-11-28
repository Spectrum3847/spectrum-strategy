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
  applyEdit,
  type Brief,
  briefDoc,
  type Edit,
  parseBrief,
} from "./brief";

const watchBriefs = (onItems: (items: Brief[]) => void, onError: () => void) =>
  onSnapshot(
    collection(db, "matchBriefs"),
    (snap) => onItems(snap.docs.map((d) => parseBrief(d.id, d.data()))),
    (error) => {
      console.warn("Could not read matchBriefs", error);
      onError();
    },
  );

export function useBriefs(): Feed<Brief> {
  const signedIn = useAuth().status === "signed-in";
  const store = signedIn
    ? storeFor("matchBriefs", () => feedStore<Brief>(watchBriefs))
    : null;
  return useStore(store, idleFeed);
}

export function saveBrief(
  prev: Brief,
  edit: Edit,
  author: Author,
  label: string,
): Promise<string> {
  const next = applyEdit(prev, edit, author, Date.now());
  return enqueueWrite(`matchBriefs/${next.id}`, briefDoc(next), label);
}
