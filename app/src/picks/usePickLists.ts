import { collection } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import {
  type Feed,
  feedStore,
  idleFeed,
  storeFor,
  useStore,
} from "../data/store";
import { watchTracked } from "../data/syncState";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import { type PickList, parsePickList, pickListDoc } from "./pickList";

const watchLists = (
  onItems: (items: PickList[]) => void,
  onError: () => void,
) =>
  watchTracked(
    "picks",
    collection(db, "pickLists"),
    (snap) => onItems(snap.docs.map((d) => parsePickList(d.id, d.data()))),
    (error) => {
      console.warn("Could not read pickLists", error);
      onError();
    },
  );

export function usePickLists(): Feed<PickList> {
  const signedIn = useAuth().status === "signed-in";
  const store = signedIn
    ? storeFor("pickLists", () => feedStore<PickList>(watchLists))
    : null;
  return useStore(store, idleFeed);
}

export const pickListPath = (id: string) => `pickLists/${id}`;

const written = new Map<string, number>();
export const lastWrittenMs = (id: string) => written.get(id) ?? 0;

export function savePickList(next: PickList, label: string): Promise<string> {
  written.set(next.id, next.updatedMs);
  return enqueueWrite(pickListPath(next.id), pickListDoc(next), label);
}
