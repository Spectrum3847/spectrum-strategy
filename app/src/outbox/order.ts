import type { OutboxStatus } from "./confirm";

export type WriteKind = "set" | "merge" | "delete";

export function supersede<
  T extends { path: string; status: OutboxStatus; kind?: WriteKind },
>(
  items: T[],
  path: string,
  kind: WriteKind = "set",
): { kept: T[]; dropped: T[] } {
  if (kind === "merge") return { kept: [...items], dropped: [] };
  const kept: T[] = [];
  const dropped: T[] = [];
  for (const item of items) {
    const pending = item.status === "on-device" || item.status === "sending";
    (item.path === path && pending ? dropped : kept).push(item);
  }
  return { kept, dropped };
}

export const sendOrder = <T>(items: T[]): T[] => [...items].reverse();
