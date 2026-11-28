import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  query,
  where,
} from "firebase/firestore";
import { db } from "../firebase/client";
import type { ProfileName } from "./roster";

type Stop = () => void;

export interface Seen<T> {
  value: T;
  fromCache: boolean;
}

export function watchSchedule(
  eventKey: string,
  onSeen: (seen: Seen<unknown>) => void,
  onError: () => void,
): Stop {
  return onSnapshot(
    doc(db, "scoutShifts", eventKey),
    (snap) =>
      onSeen({
        value: snap.exists() ? snap.data() : null,
        fromCache: snap.metadata.fromCache,
      }),
    onError,
  );
}

export function watchTrades(
  eventKey: string,
  onSeen: (seen: Seen<unknown[]>) => void,
  onError: () => void,
): Stop {
  return onSnapshot(
    query(collection(db, "shiftTrades"), where("eventKey", "==", eventKey)),
    (snap) =>
      onSeen({
        value: snap.docs.map((d) => ({ id: d.id, ...d.data() })),
        fromCache: snap.metadata.fromCache,
      }),
    onError,
  );
}

export async function fetchProfiles(): Promise<ProfileName[] | null> {
  try {
    const snap = await getDocs(collection(db, "userProfiles"));
    return snap.docs.map((d) => {
      const name = d.data().displayName;
      return { uid: d.id, displayName: typeof name === "string" ? name : "" };
    });
  } catch {
    return null;
  }
}
