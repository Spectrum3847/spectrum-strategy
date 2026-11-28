import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import {
  type Correction,
  type CorrectionAuthor,
  type HistoryHow,
  nextCorrection,
} from "../data/corrections";
import type { EventEntry } from "../data/parse";
import { saveCorrection } from "../data/useCorrections";
import { useOutbox } from "../outbox/useOutbox";
import type { Values } from "../scout/config";
import { DeliveryLine } from "../scout/ScoutForm";
import { useTrainingSession } from "../training/session";
import type { Corrected } from "./apply";
import { appendHistory, diffFields, stamp } from "./history";
import { entryLabel } from "./rows";

export function useCorrector(eventKey: string): {
  canCorrect: boolean;
  author: CorrectionAuthor;
} {
  const auth = useAuth();
  const roles = useRoles();
  const training = useTrainingSession() !== null;
  const canCorrect =
    roles.status === "ready" &&
    isLead(roles.roles) &&
    auth.status === "signed-in" &&
    auth.uid !== null &&
    eventKey !== "" &&
    !training;
  return {
    canCorrect,
    author: {
      uid: auth.uid ?? "",
      displayName:
        (roles.status === "ready" ? roles.displayName : "") ||
        auth.displayName ||
        "",
    },
  };
}

export async function saveEntryCorrection(
  entry: Corrected<EventEntry>,
  team: number,
  eventKey: string,
  author: CorrectionAuthor,
  fields: Values,
  note: string,
  how: HistoryHow = "form",
): Promise<Correction> {
  const now = Date.now();
  const changes = diffFields(
    entry.fieldValues,
    { ...entry.rawValues, ...fields },
    [...Object.keys(entry.correction?.fields ?? {}), ...Object.keys(fields)],
  );
  const next = nextCorrection(
    entry.correction,
    entry.id,
    eventKey,
    fields,
    note,
    author,
    now,
    appendHistory(
      entry.correction?.history ?? [],
      stamp(changes, how, author, now),
    ),
  );
  await saveCorrection(
    next,
    `Correction for team ${team}, ${entryLabel(entry)}`,
  );
  return next;
}

export function CorrectionDelivery({ entryId }: { entryId: string }) {
  const signedIn = useAuth().status === "signed-in";
  const sent = useOutbox().find(
    (i) => i.path === `entryCorrections/${entryId}`,
  );
  if (!sent) return null;
  return (
    <p className="secondary" role="status">
      <DeliveryLine
        delivery={{
          status: sent.status,
          ...(sent.error ? { error: sent.error } : {}),
        }}
        signedIn={signedIn}
      />
    </p>
  );
}
