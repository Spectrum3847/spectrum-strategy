import type { OutboxItem } from "../outbox/outbox";

export function sentMs(item: OutboxItem): number | null {
  const data = item.data as { updatedAtTs?: { __ts?: [number, number] } };
  const pair = data.updatedAtTs?.__ts;
  return pair ? pair[0] * 1000 + Math.floor(pair[1] / 1e6) : null;
}
