import { Timestamp } from "firebase/firestore";
import { stampAfter, stampFields } from "../forms/document";
import { removeOf, unionOf } from "../outbox/serialize";
import { maxPhotos } from "./resize";

export function workerOrigin(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  const origin = trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
  return origin.startsWith("https://") ? origin : null;
}

export const uploadUrl = (origin: string) => `${origin}/photos`;

export const photoUrl = (origin: string, key: string) =>
  `${origin}/photos/${encodeURIComponent(key)}`;

export function cleanKeys(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  for (const key of raw) {
    if (typeof key === "string" && key !== "") seen.add(key);
  }
  return [...seen];
}

export interface Attached {
  write: Record<string, unknown> | null;
  held: string[];
}

const storedStamp = (data: Record<string, unknown>) =>
  data.updatedAtTs instanceof Timestamp
    ? data.updatedAtTs.toMillis()
    : undefined;

export function withKeys(
  data: Record<string, unknown>,
  keys: readonly string[],
  now: Date,
): Attached {
  const current = cleanKeys(data.photoKeys);
  const room = Math.max(0, maxPhotos - current.length);
  const added = [...new Set(keys.filter((k) => !current.includes(k)))].slice(
    0,
    room,
  );
  const held = keys.filter((k) => current.includes(k) || added.includes(k));
  if (added.length === 0) return { write: null, held };
  return {
    write: {
      photoKeys: unionOf(added),
      ...stampFields(stampAfter(storedStamp(data), now)),
    },
    held,
  };
}

export function withoutKey(
  data: Record<string, unknown>,
  key: string,
  now: Date,
): Record<string, unknown> | null {
  if (!cleanKeys(data.photoKeys).includes(key)) return null;
  return {
    photoKeys: removeOf([key]),
    ...stampFields(stampAfter(storedStamp(data), now)),
  };
}
