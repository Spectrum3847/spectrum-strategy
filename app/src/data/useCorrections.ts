import { collection, onSnapshot, query, where } from "firebase/firestore";
import { useAuth } from "../auth/AuthProvider";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import { useTrainingSession } from "../training/session";
import { type Correction, correctionDoc, parseCorrection } from "./corrections";
import { type Feed, feedStore, idleFeed, storeFor, useStore } from "./store";

const watchCorrections =
  (eventKey: string) =>
  (onItems: (items: Correction[]) => void, onError: () => void) =>
    onSnapshot(
      query(
        collection(db, "entryCorrections"),
        where("eventKey", "==", eventKey),
      ),
      (snap) => onItems(snap.docs.map((d) => parseCorrection(d.id, d.data()))),
      (error) => {
        console.warn("Could not read entryCorrections", error);
        onError();
      },
    );

export function useCorrections(eventKey: string): Feed<Correction> {
  const signedIn = useAuth().status === "signed-in" && eventKey !== "";
  const training = useTrainingSession() !== null;
  const store =
    signedIn && !training
      ? storeFor(`entryCorrections:${eventKey}`, () =>
          feedStore<Correction>(watchCorrections(eventKey)),
        )
      : null;
  return useStore(store, idleFeed);
}

export async function saveCorrection(
  correction: Correction,
  label: string,
): Promise<void> {
  await enqueueWrite(
    `entryCorrections/${correction.id}`,
    correctionDoc(correction),
    label,
  );
}
