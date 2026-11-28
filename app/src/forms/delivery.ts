import { enqueueMerge, enqueueWrite, type OutboxItem } from "../outbox/outbox";
import type { Delivery } from "../scout/ScoutForm";
import { entryCollection, type FormKind } from "./kinds";

export const entryPath = (kind: FormKind, id: string) =>
  `${entryCollection[kind]}/${id}`;

export async function persistForm(
  kind: FormKind,
  doc: Record<string, unknown>,
  label: string,
): Promise<void> {
  await enqueueWrite(entryPath(kind, String(doc.id)), doc, label);
}

export async function persistMerge(
  kind: FormKind,
  id: string,
  fields: Record<string, unknown>,
  label: string,
): Promise<void> {
  await enqueueMerge(entryPath(kind, id), fields, label);
}

export function deliveryAt(
  outbox: OutboxItem[],
  kind: FormKind,
  id: string,
): Delivery | undefined {
  const item = outbox.find((i) => i.path === entryPath(kind, id));
  if (!item) return undefined;
  return {
    status: item.status,
    ...(item.error ? { error: item.error } : {}),
  };
}

export function unsentCount(outbox: OutboxItem[], kind: FormKind): number {
  const prefix = `${entryCollection[kind]}/`;
  return outbox.filter(
    (i) =>
      i.path.startsWith(prefix) &&
      (i.status === "on-device" || i.status === "sending"),
  ).length;
}
