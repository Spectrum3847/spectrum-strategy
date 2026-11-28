import { describe, expect, it } from "vitest";
import type { SyncNote } from "../data/syncState";
import {
  apiSource,
  type FreshnessInput,
  firestoreSource,
  freshnessOf,
  longAgo,
  shortAgo,
} from "./freshness";

const now = Date.UTC(2027, 2, 5, 12, 0, 0);
const min = 60_000;

const live: SyncNote = {
  open: true,
  fromCache: false,
  lastServerMs: now,
  failed: false,
};

const input = (over: Partial<FreshnessInput> = {}): FreshnessInput => ({
  online: true,
  pending: 0,
  refused: 0,
  notes: { entries: live, pit: live, picks: live },
  now,
  ...over,
});

describe("ages", () => {
  it("reads short and long", () => {
    expect(shortAgo(null, now)).toBe("");
    expect(shortAgo(now - 20_000, now)).toBe("just now");
    expect(shortAgo(now - 5 * min, now)).toBe("5m");
    expect(shortAgo(now - 120 * min, now)).toBe("2h");
    expect(shortAgo(now - 72 * 60 * min, now)).toBe("3d");
    expect(longAgo(null, now)).toBe("never");
    expect(longAgo(now - min, now)).toBe("1 minute ago");
    expect(longAgo(now - 5 * min, now)).toBe("5 minutes ago");
    expect(longAgo(now - 3 * 60 * min, now)).toBe("3 hours ago");
  });
});

describe("firestoreSource", () => {
  it("is live while the listener hears the server", () => {
    expect(firestoreSource("entries", live, true)).toMatchObject({
      level: "ok",
      live: true,
    });
  });

  it("says a listener never opened says nothing about being out of date", () => {
    expect(firestoreSource("pit", undefined, true)).toMatchObject({
      unopened: true,
      updatedMs: null,
    });
    expect(
      firestoreSource("pit", { ...live, open: false }, true).unopened,
    ).toBe(true);
  });

  it("flags a failed read and an offline device", () => {
    expect(
      firestoreSource("entries", { ...live, failed: true }, true).level,
    ).toBe("attention");
    expect(firestoreSource("entries", live, false)).toMatchObject({
      level: "attention",
      updatedMs: now,
    });
  });

  it("waits on the cache until the server answers", () => {
    const cached = { ...live, fromCache: true, lastServerMs: null };
    expect(firestoreSource("entries", cached, true)).toMatchObject({
      level: "idle",
      updatedMs: null,
    });
  });
});

describe("apiSource", () => {
  const at = new Date(now - 4 * min).toISOString();
  it("reads each state of an event data feed", () => {
    const of = (status: "none" | "loading" | "ready" | "failed") =>
      apiSource({ name: "TBA", status, fetchedAt: at }, true);
    expect(of("ready")).toMatchObject({
      level: "ok",
      updatedMs: now - 4 * min,
    });
    expect(of("loading").level).toBe("idle");
    expect(of("failed").level).toBe("attention");
    expect(of("none").level).toBe("idle");
    expect(
      apiSource({ name: "TBA", status: "ready", fetchedAt: null }, false),
    ).toMatchObject({ level: "attention", updatedMs: null });
  });
});

describe("freshnessOf", () => {
  it("answers yes when everything is live and nothing is unsent", () => {
    const f = freshnessOf(input());
    expect(f.headline).toBe("Synced");
    expect(f.level).toBe("ok");
    expect(f.answer).toMatch(/^Yes/);
    expect(f.pillLabel).toBe("Synced");
  });

  it("puts the unsent count in the pill and the answer", () => {
    const f = freshnessOf(input({ pending: 2 }));
    expect(f.pillLabel).toBe("Synced, 2 unsent");
    expect(f.level).toBe("attention");
    expect(f.answer).toBe(
      "Not yet. 2 entries on this device have not reached the database.",
    );
    expect(freshnessOf(input({ pending: 1 })).answer).toBe(
      "Not yet. 1 entry on this device has not reached the database.",
    );
  });

  it("calls refused writes a blocked sync", () => {
    const f = freshnessOf(input({ refused: 1 }));
    expect(f.headline).toBe("Sync blocked");
    expect(f.answer).toMatch(/refused by the database/);
    expect(f.unsent).toBe(1);
  });

  it("says offline with when it last synced", () => {
    const f = freshnessOf(
      input({
        online: false,
        notes: { entries: { ...live, lastServerMs: now - 5 * min } },
      }),
    );
    expect(f.headline).toBe("Offline, last synced 5m");
    expect(f.level).toBe("attention");
  });

  it("does not count unopened sources against the answer", () => {
    const f = freshnessOf(input({ notes: { entries: live } }));
    expect(f.level).toBe("ok");
    expect(f.sources.map((s) => s.name)).toEqual([
      "Scouting entries",
      "Pit scouting",
      "Pick lists",
    ]);
  });

  it("adds the event data rows when given them", () => {
    const f = freshnessOf(
      input({
        event: [
          { name: "TBA", status: "failed", fetchedAt: null },
          { name: "Statbotics", status: "ready", fetchedAt: null },
        ],
      }),
    );
    expect(f.sources).toHaveLength(5);
    expect(f.level).toBe("attention");
  });

  it("waits quietly while the entries listener is on the cache", () => {
    const f = freshnessOf(
      input({
        notes: {
          entries: { ...live, fromCache: true, lastServerMs: null },
        },
      }),
    );
    expect(f.headline).toBe("Syncing");
    expect(f.level).toBe("idle");
  });
});
