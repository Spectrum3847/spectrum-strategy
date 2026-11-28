import { maxPhotos } from "./resize";

export type PhotoState =
  | "waiting"
  | "uploading"
  | "uploaded"
  | "failed"
  | "attached";

export const waitingEntry = "waiting";

export const waitingText =
  "Waiting for the form: this photo joins the team's entry when it is saved.";

export interface PhotoItem {
  id: string;
  entryId: string;
  team: number;
  eventKey?: string;
  blob: Blob;
  createdAt: string;
  state: PhotoState;
  key?: string;
  attempts: number;
  error?: string;
  retryAt?: number;
}

export type UnavailableReason =
  | "offline"
  | "signed-out"
  | "unconfigured"
  | "training";

export type Outcome =
  | { type: "unavailable"; reason: UnavailableReason }
  | { type: "network" }
  | { type: "response"; status: number; key?: string };

export const maxAttempts = 5;
export const retryGapMs = 15_000;
const attachedKeepMs = 24 * 60 * 60 * 1000;
const staleMs = 14 * 24 * 60 * 60 * 1000;

const unavailableText: Record<UnavailableReason, string> = {
  offline: "Waiting for a connection",
  "signed-out": "Sign in to upload",
  unconfigured:
    "Photo storage is not set up, so this photo stays on this device",
  training: "Training mode does not upload photos",
};

export function newItem(
  id: string,
  entryId: string,
  team: number,
  blob: Blob,
  now: Date,
  eventKey?: string,
): PhotoItem {
  return {
    id,
    entryId,
    team,
    ...(eventKey !== undefined && { eventKey }),
    blob,
    createdAt: now.toISOString(),
    state: "waiting",
    attempts: 0,
  };
}

function retryOrFail(item: PhotoItem, message: string, nowMs: number) {
  const attempts = item.attempts + 1;
  if (attempts >= maxAttempts) {
    return { ...item, state: "failed" as const, attempts, error: message };
  }
  return {
    ...item,
    state: "waiting" as const,
    attempts,
    error: message,
    retryAt: nowMs + retryGapMs,
  };
}

function failed(item: PhotoItem, message: string): PhotoItem {
  return { ...item, state: "failed", error: message };
}

export function settle(
  item: PhotoItem,
  outcome: Outcome,
  nowMs: number,
): PhotoItem {
  const { retryAt: _gone, ...base } = item;
  if (outcome.type === "unavailable") {
    const { error: _old, ...rest } = base;
    return {
      ...rest,
      state: "waiting",
      error: unavailableText[outcome.reason],
    };
  }
  if (outcome.type === "network") {
    return retryOrFail(base, "Could not reach the photo server", nowMs);
  }
  const { status, key } = outcome;
  if (status === 201 && key) {
    const { error: _old, ...rest } = base;
    return { ...rest, state: "uploaded", key };
  }
  if (status === 413) {
    return failed(base, "Too large for the photo server (2 MB limit)");
  }
  if (status === 415)
    return failed(base, "The photo server does not take this image type");
  if (status === 401 || status === 403) {
    return retryOrFail(
      base,
      "The photo server refused this sign-in. Sign out and back in",
      nowMs,
    );
  }
  if (status >= 500 || status === 201) {
    return retryOrFail(base, "The photo server had a problem", nowMs);
  }
  return failed(base, `The photo server refused it (${status})`);
}

export function due(item: PhotoItem, nowMs: number): boolean {
  return item.state === "waiting" && (item.retryAt ?? 0) <= nowMs;
}

export function retried(item: PhotoItem): PhotoItem {
  const { error: _e, retryAt: _r, ...rest } = item;
  return { ...rest, state: "waiting", attempts: 0 };
}

export function isStale(item: PhotoItem, nowMs: number): boolean {
  const age = nowMs - Date.parse(item.createdAt);
  return item.state === "attached" ? age > attachedKeepMs : age > staleMs;
}

export interface Slot {
  id: string;
  key: string | null;
  item: PhotoItem | null;
}

export function buildSlots(
  existingKeys: readonly string[],
  removed: ReadonlySet<string>,
  items: readonly PhotoItem[],
): Slot[] {
  const mine = items
    .filter((i) => !removed.has(i.id) && !(i.key && removed.has(i.key)))
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  const itemKeys = new Set(mine.flatMap((i) => (i.key ? [i.key] : [])));
  const kept: Slot[] = existingKeys
    .filter((k) => !removed.has(k) && !itemKeys.has(k))
    .map((key) => ({ id: key, key, item: null }));
  return [
    ...kept,
    ...mine.map((item) => ({ id: item.id, key: item.key ?? null, item })),
  ];
}

export const slotKeys = (slots: readonly Slot[]): string[] =>
  slots.flatMap((s) => (s.key ? [s.key] : []));

export const canAdd = (slots: readonly Slot[]) => slots.length < maxPhotos;

export function slotText(item: PhotoItem | null): string {
  if (item === null) return "Uploaded";
  switch (item.state) {
    case "waiting":
      return item.error ?? "Waiting to upload";
    case "uploading":
      return "Uploading";
    case "uploaded":
    case "attached":
      return "Uploaded";
    case "failed":
      return item.error ?? "Upload failed";
  }
}
