import { doc, getDoc } from "firebase/firestore";
import { db } from "../firebase/client";
import { enqueueMerge } from "../outbox/outbox";
import { withKeys, withoutKey } from "./keys";

const pathOf = (entryId: string) => `pitScoutEntries/${entryId}`;

export async function attachKeys(
  entryId: string,
  keys: string[],
): Promise<string[]> {
  const snap = await getDoc(doc(db, pathOf(entryId)));
  const data = snap.data();
  if (!snap.exists() || !data) return [];
  const { write, held } = withKeys(data, keys, new Date());
  if (write) {
    await enqueueMerge(
      pathOf(entryId),
      write,
      `Pit photos, team ${data.teamNumber}`,
    );
  }
  return held;
}

export type Detached = "queued" | "absent" | "no-entry";

export async function detachKey(
  entryId: string,
  key: string,
): Promise<Detached> {
  const snap = await getDoc(doc(db, pathOf(entryId)));
  const data = snap.data();
  if (!snap.exists() || !data) return "no-entry";
  const write = withoutKey(data, key, new Date());
  if (!write) return "absent";
  await enqueueMerge(
    pathOf(entryId),
    write,
    `Pit photo removed, team ${data.teamNumber}`,
  );
  return "queued";
}
