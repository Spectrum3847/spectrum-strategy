import {
  collection,
  doc,
  getDoc,
  onSnapshot,
  query,
  where,
} from "firebase/firestore";
import { type EventEntry, parseEventEntry } from "../data/parse";
import { watchTracked } from "../data/syncState";
import { db } from "../firebase/client";

type Stop = () => void;

export function watchScoutConfig(onJson: (json: string) => void): Stop {
  return onSnapshot(
    doc(db, "appConfig", "scoutConfig"),
    (snap) => {
      const json = snap.data()?.configJson;
      if (typeof json === "string") onJson(json);
    },
    () => undefined,
  );
}

export function watchActiveEvent(onKey: (key: string | null) => void): Stop {
  return onSnapshot(
    doc(db, "appConfig", "activeEvent"),
    (snap) => {
      const key = snap.data()?.eventKey;
      onKey(typeof key === "string" ? key.trim() : null);
    },
    () => onKey(null),
  );
}

export async function fetchTbaKey(): Promise<string | null> {
  const snap = await getDoc(doc(db, "appConfig", "apiKeys"));
  const key = snap.data()?.tba;
  return typeof key === "string" ? key.trim() : null;
}

export function watchScoutShifts(
  eventKey: string,
  onShifts: (data: unknown) => void,
): Stop {
  return onSnapshot(
    doc(db, "scoutShifts", eventKey),
    (snap) => onShifts(snap.exists() ? snap.data() : null),
    () => undefined,
  );
}

export function watchShiftTrades(
  eventKey: string,
  onTrades: (docs: unknown[]) => void,
): Stop {
  return onSnapshot(
    query(collection(db, "shiftTrades"), where("eventKey", "==", eventKey)),
    (snap) => onTrades(snap.docs.map((d) => d.data())),
    () => undefined,
  );
}

export function eventEntriesQuery(eventKey: string) {
  const prefix = `${eventKey}_`;
  return query(
    collection(db, "scoutEntries"),
    where("tbaMatchKey", ">=", prefix),
    where("tbaMatchKey", "<", `${prefix}\uf8ff`),
  );
}

export function watchEventEntries(
  eventKey: string,
  onEntries: (entries: EventEntry[]) => void,
  onError: () => void = () => undefined,
): Stop {
  return watchTracked(
    "entries",
    eventEntriesQuery(eventKey),
    (snap) => onEntries(snap.docs.map((d) => parseEventEntry(d.id, d.data()))),
    (error) => {
      console.warn("Could not read the event's entries", error);
      onError();
    },
  );
}
