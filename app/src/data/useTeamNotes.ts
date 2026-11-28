import { collection, onSnapshot, query, where } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import { db } from "../firebase/client";
import { type Feed, feedStore, idleFeed, storeFor, useStore } from "./store";
import { parseTeamNote, type TeamNote } from "./teamNotes";

const watchNotes =
  (eventKey: string) =>
  (onItems: (items: TeamNote[]) => void, onError: () => void) =>
    onSnapshot(
      query(collection(db, "teamNotes"), where("eventKey", "==", eventKey)),
      (snap) => onItems(snap.docs.map((d) => parseTeamNote(d.id, d.data()))),
      (error) => {
        console.warn("Could not read teamNotes", error);
        onError();
      },
    );

export function useTeamNotes(eventKey: string): Feed<TeamNote> {
  const signedIn = useAuth().status === "signed-in" && eventKey !== "";
  const store = signedIn
    ? storeFor(`teamNotes:${eventKey}`, () =>
        feedStore<TeamNote>(watchNotes(eventKey)),
      )
    : null;
  return useStore(store, idleFeed);
}
