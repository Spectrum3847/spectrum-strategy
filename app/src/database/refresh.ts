import { collection, getDocsFromServer } from "firebase/firestore";
import { db } from "../firebase/client";
import { resendNow } from "../outbox/outbox";
import { eventEntriesQuery } from "../scout/remote";
import type { Kind } from "./rows";
import { seasonOf, seasonQuery } from "./useAllEntries";

const collections: Record<Kind, string> = {
  match: "scoutEntries",
  pit: "pitScoutEntries",
  prescout: "prescoutEntries",
};

export async function refreshFromServer(
  kind: Kind,
  eventKey: string,
  allEvents: boolean,
): Promise<void> {
  resendNow();
  const season = seasonOf(eventKey);
  const target =
    kind !== "match" || eventKey === ""
      ? collection(db, collections[kind])
      : allEvents && season !== null
        ? seasonQuery(season)
        : eventEntriesQuery(eventKey);
  await getDocsFromServer(target);
}
