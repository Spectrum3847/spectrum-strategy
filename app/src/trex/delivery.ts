import type { OutboxItem } from "../outbox/outbox";
import type { Delivery } from "../scout/ScoutForm";

export const reportPath = (id: string) => `trexTraitReports/${id}`;

export function deliveryOf(
  outbox: OutboxItem[],
  id: string,
): Delivery | undefined {
  const item = outbox.find((i) => i.path === reportPath(id));
  if (!item) return undefined;
  return {
    status: item.status,
    ...(item.error ? { error: item.error } : {}),
  };
}

export const unsentReports = (outbox: OutboxItem[]) =>
  outbox.filter(
    (i) =>
      i.path.startsWith("trexTraitReports/") &&
      (i.status === "on-device" || i.status === "sending"),
  ).length;
