import { useAuth } from "../auth/AuthProvider";
import { canDeleteEntry } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { enqueueDelete, getOutbox, subscribeOutbox } from "../outbox/outbox";
import { whenInDatabase } from "../outbox/settled";
import { photoQueue } from "../photos/service";
import { isTraining } from "../training/session";
import { entryPath } from "./delivery";
import type { FormKind } from "./kinds";

export function useDeleteGate(): (authorUid: string | undefined) => boolean {
  const { uid } = useAuth();
  const roles = useRoles();
  return (authorUid) =>
    !isTraining() &&
    roles.status === "ready" &&
    canDeleteEntry(roles.roles, uid, authorUid ?? "");
}

export function useCanDelete(authorUid: string | undefined): boolean {
  return useDeleteGate()(authorUid);
}

export async function deleteFormEntry(
  kind: FormKind,
  id: string,
  label: string,
  photoKeys: readonly string[] = [],
): Promise<void> {
  const path = entryPath(kind, id);
  await enqueueDelete(path, label);
  if (kind === "pit") {
    removePhotosOnceDeleted(path, id, photoKeys).catch((e) =>
      console.warn("Could not remove the deleted entry's photos", e),
    );
  }
}

export async function removePhotosOnceDeleted(
  path: string,
  id: string,
  photoKeys: readonly string[],
): Promise<boolean> {
  if (!(await whenInDatabase(path, getOutbox, subscribeOutbox))) return false;
  await photoQueue.start();
  for (const item of photoQueue.items().filter((i) => i.entryId === id)) {
    await photoQueue.discard(item.id);
  }
  await photoQueue.release(photoKeys);
  return true;
}
