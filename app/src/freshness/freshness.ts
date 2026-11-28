import type { SyncNote, SyncSource } from "../data/syncState";

export type Level = "ok" | "idle" | "attention";

export interface Source {
  name: string;
  status: string;
  level: Level;
  live?: boolean;
  unopened?: boolean;
  updatedMs: number | null;
}

export interface Freshness {
  headline: string;
  level: Level;
  unsent: number;
  refused: number;
  sources: Source[];
  answer: string;
  pillLabel: string;
}

export function shortAgo(ms: number | null, now: number): string {
  if (ms === null) return "";
  const minutes = Math.floor((now - ms) / 60_000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  return hours < 48 ? `${hours}h` : `${Math.floor(hours / 24)}d`;
}

export function longAgo(ms: number | null, now: number): string {
  if (ms === null) return "never";
  const minutes = Math.floor((now - ms) / 60_000);
  const unit = (n: number, word: string) =>
    `${n} ${word}${n === 1 ? "" : "s"} ago`;
  if (minutes < 1) return "just now";
  if (minutes < 60) return unit(minutes, "minute");
  const hours = Math.floor(minutes / 60);
  return hours < 48 ? unit(hours, "hour") : unit(Math.floor(hours / 24), "day");
}

export const sourceNames: Record<SyncSource, string> = {
  entries: "Scouting entries",
  pit: "Pit scouting",
  picks: "Pick lists",
};

export function firestoreSource(
  source: SyncSource,
  note: SyncNote | undefined,
  online: boolean,
): Source {
  const name = sourceNames[source];
  if (!note?.open) {
    return {
      name,
      status:
        "Not loaded on this device yet. It loads when you open that screen.",
      level: "idle",
      unopened: true,
      updatedMs: note?.lastServerMs ?? null,
    };
  }
  if (note.failed) {
    return {
      name,
      status: "Could not read this. It may be incomplete.",
      level: "attention",
      updatedMs: note.lastServerMs,
    };
  }
  if (!online) {
    return {
      name,
      status: "No connection. Showing what this device saved.",
      level: "attention",
      updatedMs: note.lastServerMs,
    };
  }
  if (note.fromCache) {
    return {
      name,
      status: "Waiting for the server. Showing what this device saved.",
      level: "idle",
      updatedMs: note.lastServerMs,
    };
  }
  return {
    name,
    status: "Live from the server",
    level: "ok",
    live: true,
    updatedMs: note.lastServerMs,
  };
}

export type ApiState = "none" | "loading" | "ready" | "failed";

export interface ApiInput {
  name: string;
  status: ApiState;
  fetchedAt: string | null;
}

export function apiSource(input: ApiInput, online: boolean): Source {
  const at =
    input.fetchedAt === null ? Number.NaN : Date.parse(input.fetchedAt);
  const updatedMs = Number.isNaN(at) ? null : at;
  const base = { name: input.name, updatedMs };
  switch (input.status) {
    case "loading":
      return { ...base, status: "Refreshing", level: "idle" };
    case "failed":
      return { ...base, status: "Could not load", level: "attention" };
    case "none":
      return { ...base, status: "Not loaded yet", level: "idle" };
    case "ready":
      return online
        ? { ...base, status: "Loaded", level: "ok" }
        : {
            ...base,
            status: "No connection. Showing saved data.",
            level: "attention",
          };
  }
}

const rank: Record<Level, number> = { ok: 0, idle: 1, attention: 2 };

function levelOf(sources: Source[], unsent: number, refused: number): Level {
  let level: Level = "ok";
  for (const s of sources) {
    if (s.unopened) continue;
    if (rank[s.level] > rank[level]) level = s.level;
  }
  return unsent + refused > 0 ? "attention" : level;
}

function answerFor(level: Level, refused: number, pending: number): string {
  if (refused > 0) {
    const noun = refused === 1 ? "entry was" : "entries were";
    return `Not yet. ${refused} ${noun} refused by the database and will not send until that is fixed.`;
  }
  if (pending > 0) {
    const noun = pending === 1 ? "entry" : "entries";
    return `Not yet. ${pending} ${noun} on this device ${pending === 1 ? "has" : "have"} not reached the database.`;
  }
  if (level === "ok") return "Yes. This device is in sync.";
  if (level === "idle") {
    return "Nothing is out of date, but this device is still waiting for the server.";
  }
  return "Not sure. A source below is offline or failing, so this device may be behind.";
}

export interface FreshnessInput {
  online: boolean;
  pending: number;
  refused: number;
  notes: Partial<Record<SyncSource, SyncNote>>;
  event?: ApiInput[];
  now: number;
}

export function freshnessOf(input: FreshnessInput): Freshness {
  const { online, pending, refused, notes, now } = input;
  const sources = (["entries", "pit", "picks"] as const).map((s) =>
    firestoreSource(s, notes[s], online),
  );
  for (const api of input.event ?? []) sources.push(apiSource(api, online));
  const entries = sources[0] as Source;
  const unsent = pending + refused;
  const last = shortAgo(entries.updatedMs, now);
  const headline =
    refused > 0
      ? "Sync blocked"
      : !online
        ? last === ""
          ? "Offline"
          : `Offline, last synced ${last}`
        : entries.unopened
          ? "Not loaded"
          : entries.level === "idle"
            ? "Syncing"
            : entries.level === "attention"
              ? "Not syncing"
              : "Synced";
  const level = levelOf(sources, pending, refused);
  return {
    headline,
    level,
    unsent,
    refused,
    sources,
    answer: answerFor(level, refused, pending),
    pillLabel: unsent > 0 ? `${headline}, ${unsent} unsent` : headline,
  };
}
