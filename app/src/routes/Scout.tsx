import { useCallback, useState, useSyncExternalStore } from "react";
import { useNavigate } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { useFormConfig, usePitEntries } from "../data/useCollections";
import { useCanDelete } from "../forms/deleteEntry";
import { ModeTabs } from "../forms/ModeTabs";
import { useOutbox } from "../outbox/useOutbox";
import { AlertBanner } from "../scout/AlertBanner";
import {
  standInStore,
  stationStore,
  useLockedStation,
  useSavedEntries,
  useStandIn,
} from "../scout/local";
import { PreEventCard, showPreEvent } from "../scout/PreEventCard";
import { deliveryFrom, persistEntry, removeEntry } from "../scout/persist";
import { useScoutData } from "../scout/ScoutData";
import { ScoutForm } from "../scout/ScoutForm";
import { useAccuracyAlerts } from "../scout/useAccuracyAlerts";
import { useTrainingSession } from "../training/session";

const subscribeOnline = (notify: () => void) => {
  window.addEventListener("online", notify);
  window.addEventListener("offline", notify);
  return () => {
    window.removeEventListener("online", notify);
    window.removeEventListener("offline", notify);
  };
};

export function Scout() {
  const data = useScoutData();
  const auth = useAuth();
  const saved = useSavedEntries();
  const outbox = useOutbox();
  const online = useSyncExternalStore(
    subscribeOnline,
    () => navigator.onLine,
    () => true,
  );
  const [station, setStation] = useState(stationStore.get);
  const locked = useLockedStation();
  const standIn = useStandIn();
  const canDelete = useCanDelete(auth.uid ?? undefined);

  const onStation = useCallback((next: string) => {
    stationStore.set(next);
    setStation(next);
  }, []);

  const pit = usePitEntries();
  const pitConfig = useFormConfig("pit");
  const navigate = useNavigate();
  const onScan = useCallback(() => navigate("/scout/scan"), [navigate]);

  const training = useTrainingSession() !== null;
  const { alerts, dismiss } = useAccuracyAlerts(training ? null : auth.uid);
  const mine = training
    ? []
    : outbox.filter((i) => i.path.startsWith("scoutEntries/"));
  const unsent = {
    pending: mine.filter(
      (i) => i.status === "on-device" || i.status === "sending",
    ).length,
    refused: mine.filter((i) => i.status === "refused").length,
  };
  const formKey = JSON.stringify(
    data.config.sections.map((s) => [
      s.name,
      s.fields.map((f) => [f.code, f.type, f.title]),
    ]),
  );

  return (
    <>
      <ModeTabs />
      {showPreEvent(data.eventKey, data.schedule, data.entries.length) && (
        <PreEventCard />
      )}
      <AlertBanner
        alerts={alerts}
        config={data.config}
        onDismiss={() => void dismiss(alerts)}
      />
      <ScoutForm
        key={formKey}
        config={data.config}
        schedule={data.schedule}
        eventKey={data.eventKey}
        deviceStation={locked ?? station}
        stationLocked={locked !== null}
        shifts={data.shifts}
        standIn={standIn}
        onStandIn={standInStore.set}
        author={{ uid: auth.uid, displayName: auth.displayName }}
        online={online}
        saved={saved}
        remote={data.entries}
        unsent={unsent}
        deliveryOf={deliveryFrom(outbox)}
        persist={persistEntry}
        {...(canDelete ? { remove: removeEntry } : {})}
        onStation={onStation}
        onScan={onScan}
        pit={{ entries: pit.items, config: pitConfig }}
      />
    </>
  );
}
