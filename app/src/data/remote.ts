import {
  collection,
  type DocumentData,
  doc,
  onSnapshot,
  type QuerySnapshot,
} from "firebase/firestore";
import { db } from "../firebase/client";
import {
  type PitEntry,
  type PrescoutEntry,
  parsePitEntry,
  parsePrescoutEntry,
  parseTrexReport,
  type TrexReport,
} from "./parse";
import { type SyncSource, watchTracked } from "./syncState";

type Stop = () => void;

function watchCollection<T>(
  name: string,
  parse: (id: string, data: Record<string, unknown>) => T,
  onItems: (items: T[]) => void,
  onError: () => void,
  source?: SyncSource,
): Stop {
  const target = collection(db, name);
  const onSnap = (snap: QuerySnapshot<DocumentData>) =>
    onItems(snap.docs.map((d) => parse(d.id, d.data())));
  const onFail = (error: unknown) => {
    console.warn(`Could not read ${name}`, error);
    onError();
  };
  if (source) return watchTracked(source, target, onSnap, onFail);
  return onSnapshot(target, onSnap, onFail);
}

export const watchPitEntries = (
  onItems: (items: PitEntry[]) => void,
  onError: () => void,
) => watchCollection("pitScoutEntries", parsePitEntry, onItems, onError, "pit");

export const watchPrescoutEntries = (
  onItems: (items: PrescoutEntry[]) => void,
  onError: () => void,
) => watchCollection("prescoutEntries", parsePrescoutEntry, onItems, onError);

export const watchTrexReports = (
  onItems: (items: TrexReport[]) => void,
  onError: () => void,
) => watchCollection("trexTraitReports", parseTrexReport, onItems, onError);

export function watchFormConfig(
  docId: "pitScoutConfig" | "prescoutConfig",
  onJson: (json: string) => void,
): Stop {
  return onSnapshot(
    doc(db, "appConfig", docId),
    (snap) => {
      const json = snap.data()?.configJson;
      if (typeof json === "string") onJson(json);
    },
    () => undefined,
  );
}
