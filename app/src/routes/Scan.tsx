import { useAuth } from "../auth/AuthProvider";
import { useOutbox } from "../outbox/useOutbox";
import { useSavedEntries } from "../scout/local";
import { deliveryFrom, persistEntry } from "../scout/persist";
import { ScanStation } from "../scout/ScanStation";
import { useScoutData } from "../scout/ScoutData";

export function Scan() {
  const data = useScoutData();
  const auth = useAuth();
  const saved = useSavedEntries();
  const outbox = useOutbox();
  return (
    <ScanStation
      config={data.config}
      schedule={data.schedule}
      eventKey={data.eventKey}
      author={{ uid: auth.uid, displayName: auth.displayName }}
      remote={data.entries}
      saved={saved}
      deliveryOf={deliveryFrom(outbox)}
      persist={persistEntry}
    />
  );
}
