import {
  collection,
  limit,
  onSnapshot,
  query,
  where,
} from "firebase/firestore";
import { useCallback, useEffect, useState } from "react";
import { db } from "../firebase/client";
import { enqueueMerge } from "../outbox/outbox";
import { type AccuracyAlert, parseAlert } from "./alerts";

export function useAccuracyAlerts(uid: string | null) {
  const [alerts, setAlerts] = useState<AccuracyAlert[]>([]);
  const [hidden, setHidden] = useState<ReadonlySet<string>>(new Set());

  useEffect(() => {
    setAlerts([]);
    setHidden(new Set());
    if (uid === null) return;
    return onSnapshot(
      query(
        collection(db, "accuracyAlerts"),
        where("authorUid", "==", uid),
        where("acknowledged", "==", false),
        limit(20),
      ),
      (snap) => setAlerts(snap.docs.map((d) => parseAlert(d.id, d.data()))),
      (error) => console.warn("Could not read accuracy alerts", error),
    );
  }, [uid]);

  const dismiss = useCallback(async (shown: AccuracyAlert[]) => {
    setHidden((h) => new Set([...h, ...shown.map((a) => a.entryId)]));
    await Promise.allSettled(
      shown.map((a) =>
        enqueueMerge(
          `accuracyAlerts/${a.entryId}`,
          { acknowledged: true },
          `Dismiss alert, team ${a.teamNumber}`,
        ),
      ),
    );
  }, []);

  return {
    alerts: alerts.filter((a) => !hidden.has(a.entryId)),
    dismiss,
  };
}
