import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import type { PitEntry } from "../data/parse";
import { removeOf, unionOf } from "../outbox/serialize";
import {
  cleanKeys,
  photoUrl,
  uploadUrl,
  withKeys,
  withoutKey,
  workerOrigin,
} from "./keys";
import { fitWithin, isWorkerType, maxBytes, usableOriginal } from "./resize";
import {
  buildSlots,
  canAdd,
  due,
  isStale,
  maxAttempts,
  newItem,
  type PhotoItem,
  retried,
  retryGapMs,
  settle,
  slotKeys,
  slotText,
  waitingEntry,
} from "./state";
import { placements } from "./waiting";

const blob = new Blob(["x"], { type: "image/jpeg" });
const now = new Date("2027-03-05T18:00:00.000Z");
const nowMs = now.getTime();
const waiting = newItem("p1", "e1", 1111, blob, now);

function item(over: Partial<PhotoItem> & { id: string }): PhotoItem {
  return { ...waiting, ...over };
}

describe("resize", () => {
  it("shrinks the long edge to 1280 and keeps the shape", () => {
    expect(fitWithin(4000, 3000)).toEqual({ width: 1280, height: 960 });
    expect(fitWithin(3000, 4000)).toEqual({ width: 960, height: 1280 });
    expect(fitWithin(5000, 100)).toEqual({ width: 1280, height: 26 });
  });

  it("never enlarges a small image or returns a zero side", () => {
    expect(fitWithin(800, 600)).toEqual({ width: 800, height: 600 });
    expect(fitWithin(1280, 1280)).toEqual({ width: 1280, height: 1280 });
    expect(fitWithin(100000, 10).height).toBe(1);
  });

  it("keeps an unreadable original only when the Worker would take it", () => {
    expect(usableOriginal("image/heic", 1000)).toBe(true);
    expect(usableOriginal("image/jpeg", maxBytes)).toBe(true);
    expect(usableOriginal("image/jpeg", maxBytes + 1)).toBe(false);
    expect(usableOriginal("image/gif", 1000)).toBe(false);
    expect(usableOriginal("image/jpeg", 0)).toBe(false);
    expect(isWorkerType("application/pdf")).toBe(false);
  });
});

describe("keys", () => {
  it("accepts an https origin and drops a trailing slash", () => {
    expect(workerOrigin(" https://p.example.workers.dev/ ")).toBe(
      "https://p.example.workers.dev",
    );
    expect(workerOrigin("http://p.example.workers.dev")).toBeNull();
    expect(workerOrigin("")).toBeNull();
    expect(workerOrigin(undefined)).toBeNull();
  });

  it("builds the Worker paths", () => {
    expect(uploadUrl("https://w.dev")).toBe("https://w.dev/photos");
    expect(photoUrl("https://w.dev", "a b/c.jpg")).toBe(
      "https://w.dev/photos/a%20b%2Fc.jpg",
    );
  });

  it("keeps only string keys, once each", () => {
    expect(cleanKeys(["a", "", 2, "a", "b", null])).toEqual(["a", "b"]);
    expect(cleanKeys("a")).toEqual([]);
  });

  it("adds uploaded keys as a union write with new stamps only", () => {
    const data = {
      id: "e1",
      fieldValues: { a: 1 },
      photoKeys: ["a"],
      updatedAt: "2027-01-01T00:00:00.000Z",
      updatedAtTs: Timestamp.fromDate(new Date("2027-01-01")),
    };
    const result = withKeys(data, ["b"], now);
    expect(Object.keys(result.write ?? {}).sort()).toEqual([
      "photoKeys",
      "updatedAt",
      "updatedAtTs",
    ]);
    expect(result.write?.photoKeys).toEqual(unionOf(["b"]));
    expect(result.write?.updatedAt).toBe(now.toISOString());
    expect(result.held).toEqual(["b"]);
  });

  it("never stamps earlier than the stored stamp", () => {
    const ahead = new Date(now.getTime() + 60_000);
    const data = { photoKeys: [], updatedAtTs: Timestamp.fromDate(ahead) };
    const result = withKeys(data, ["b"], now);
    expect(result.write?.updatedAt).toBe(ahead.toISOString());
    const stamp = result.write?.updatedAtTs as Timestamp | undefined;
    expect(stamp?.toMillis()).toBe(ahead.getTime());
  });

  it("writes nothing when the entry already holds the keys", () => {
    const result = withKeys({ photoKeys: ["a", "b"] }, ["b"], now);
    expect(result.write).toBeNull();
    expect(result.held).toEqual(["b"]);
  });

  it("holds at most three photos, adding only what fits", () => {
    expect(withKeys({ photoKeys: ["a", "b", "c"] }, ["d"], now)).toEqual({
      write: null,
      held: [],
    });
    const some = withKeys({ photoKeys: ["a", "b"] }, ["c", "d"], now);
    expect(some.write?.photoKeys).toEqual(unionOf(["c"]));
    expect(some.held).toEqual(["c"]);
  });

  it("takes a key off as a remove write, and skips one the entry lacks", () => {
    const data = { photoKeys: ["a", "b"] };
    const write = withoutKey(data, "a", now);
    expect(write?.photoKeys).toEqual(removeOf(["a"]));
    expect(write?.updatedAt).toBe(now.toISOString());
    expect(withoutKey(data, "z", now)).toBeNull();
  });
});

describe("waiting photos", () => {
  const entry = (over: Partial<PitEntry> & { id: string }): PitEntry => ({
    teamNumber: 1111,
    eventKey: "2027test",
    fieldValues: {},
    authorUid: "u1",
    scoutName: "Scout A",
    updatedAt: "2027-03-05T10:00:00.000Z",
    photoKeys: [],
    ...over,
  });
  const photo = (id: string, over: Partial<PhotoItem> = {}) =>
    ({
      ...newItem(id, waitingEntry, 1111, blob, now, "2027test"),
      ...over,
    }) as PhotoItem;

  it("goes to the newest entry for the team and event, whoever wrote it", () => {
    const moves = placements(
      [photo("p1"), photo("p2", { team: 2222 })],
      [
        entry({ id: "old", updatedAt: "2027-03-05T09:00:00.000Z" }),
        entry({ id: "new", authorUid: "u2" }),
        entry({ id: "other-event", eventKey: "2027zzz" }),
      ],
    );
    expect([...moves]).toEqual([["p1", "new"]]);
  });

  it("counts an entry with no event, and leaves a team with no entry waiting", () => {
    const moves = placements(
      [photo("p1"), photo("p2", { team: 3333 })],
      [entry({ id: "legacy", eventKey: "" })],
    );
    expect([...moves]).toEqual([["p1", "legacy"]]);
  });

  it("ignores photos already on an entry", () => {
    const placed = { ...photo("p1"), entryId: "e1" };
    expect(placements([placed], [entry({ id: "e1" })]).size).toBe(0);
  });
});

describe("settling an upload", () => {
  it("records the key of a 201", () => {
    const result = settle(
      item({ id: "p1", error: "old", retryAt: 5 }),
      { type: "response", status: 201, key: "k.jpg" },
      nowMs,
    );
    expect(result).toMatchObject({ state: "uploaded", key: "k.jpg" });
    expect(result.error).toBeUndefined();
    expect(result.retryAt).toBeUndefined();
  });

  it("waits without using an attempt when offline, signed out or not set up", () => {
    for (const reason of [
      "offline",
      "signed-out",
      "unconfigured",
      "training",
    ] as const) {
      const result = settle(waiting, { type: "unavailable", reason }, nowMs);
      expect(result.state).toBe("waiting");
      expect(result.attempts).toBe(0);
      expect(result.error).toBeTruthy();
    }
    expect(
      settle(waiting, { type: "unavailable", reason: "offline" }, nowMs).error,
    ).toBe("Waiting for a connection");
  });

  it("retries network and server trouble, then stops", () => {
    let current = waiting;
    for (let i = 1; i < maxAttempts; i++) {
      current = settle(current, { type: "network" }, nowMs);
      expect(current.state).toBe("waiting");
      expect(current.retryAt).toBe(nowMs + retryGapMs);
    }
    current = settle(current, { type: "response", status: 503 }, nowMs);
    expect(current.state).toBe("failed");
    expect(current.attempts).toBe(maxAttempts);
  });

  it("stops at once for a refusal that would repeat", () => {
    const tooBig = settle(waiting, { type: "response", status: 413 }, nowMs);
    expect(tooBig.state).toBe("failed");
    expect(tooBig.error).toContain("2 MB");
    expect(
      settle(waiting, { type: "response", status: 415 }, nowMs).state,
    ).toBe("failed");
    expect(
      settle(waiting, { type: "response", status: 400 }, nowMs).error,
    ).toContain("400");
  });

  it("retries a refused sign-in with advice", () => {
    const result = settle(waiting, { type: "response", status: 403 }, nowMs);
    expect(result.state).toBe("waiting");
    expect(result.error).toContain("Sign out");
  });

  it("treats a 201 without a key as a server problem", () => {
    expect(
      settle(waiting, { type: "response", status: 201 }, nowMs).state,
    ).toBe("waiting");
  });

  it("tries again only once the gap has passed", () => {
    const later = settle(waiting, { type: "network" }, nowMs);
    expect(due(later, nowMs)).toBe(false);
    expect(due(later, nowMs + retryGapMs)).toBe(true);
    expect(due(item({ id: "p", state: "failed" }), nowMs)).toBe(false);
    expect(due(item({ id: "p", state: "uploaded" }), nowMs)).toBe(false);
  });

  it("starts a retry with a clean count", () => {
    const failed = item({
      id: "p",
      state: "failed",
      attempts: 5,
      error: "x",
      retryAt: 9,
    });
    expect(retried(failed)).toMatchObject({ state: "waiting", attempts: 0 });
    expect(retried(failed).error).toBeUndefined();
  });
});

describe("old items", () => {
  const day = 24 * 60 * 60 * 1000;
  it("drops an attached item after a day and any other after two weeks", () => {
    const made = (state: PhotoItem["state"], ageDays: number) =>
      item({
        id: "p",
        state,
        createdAt: new Date(nowMs - ageDays * day).toISOString(),
      });
    expect(isStale(made("attached", 0.5), nowMs)).toBe(false);
    expect(isStale(made("attached", 2), nowMs)).toBe(true);
    expect(isStale(made("waiting", 2), nowMs)).toBe(false);
    expect(isStale(made("waiting", 15), nowMs)).toBe(true);
  });
});

describe("photo slots", () => {
  it("lists the entry's keys, then queued photos oldest first", () => {
    const a = item({ id: "a", createdAt: "2027-03-05T18:00:02.000Z" });
    const b = item({ id: "b", createdAt: "2027-03-05T18:00:01.000Z" });
    const slots = buildSlots(["k1"], new Set(), [a, b]);
    expect(slots.map((s) => s.id)).toEqual(["k1", "b", "a"]);
    expect(slots[0]).toMatchObject({ key: "k1", item: null });
  });

  it("shows a photo once when its item carries a key the entry has", () => {
    const attached = item({ id: "a", state: "attached", key: "k1" });
    const slots = buildSlots(["k1", "k2"], new Set(), [attached]);
    expect(slots.map((s) => s.id)).toEqual(["k2", "a"]);
    expect(slotKeys(slots)).toEqual(["k2", "k1"]);
  });

  it("hides what the scout removed, by id or by key", () => {
    const attached = item({ id: "a", state: "attached", key: "k1" });
    const slots = buildSlots(["k1", "k2", "k3"], new Set(["k1", "k3"]), [
      attached,
    ]);
    expect(slots.map((s) => s.id)).toEqual(["k2"]);
    expect(buildSlots([], new Set(["a"]), [attached])).toEqual([]);
  });

  it("has keys only for photos that reached the store", () => {
    const slots = buildSlots(["k1"], new Set(), [
      item({ id: "w" }),
      item({ id: "u", state: "uploaded", key: "k2" }),
    ]);
    expect(slotKeys(slots)).toEqual(["k1", "k2"]);
  });

  it("allows three photos in all", () => {
    expect(canAdd(buildSlots(["a", "b"], new Set(), []))).toBe(true);
    expect(canAdd(buildSlots(["a", "b", "c"], new Set(), []))).toBe(false);
    expect(canAdd(buildSlots(["a", "b"], new Set(), [item({ id: "w" })]))).toBe(
      false,
    );
  });

  it("says what each photo is doing", () => {
    expect(slotText(null)).toBe("Uploaded");
    expect(slotText(waiting)).toBe("Waiting to upload");
    expect(slotText(item({ id: "p", state: "uploading" }))).toBe("Uploading");
    expect(slotText(item({ id: "p", state: "attached" }))).toBe("Uploaded");
    expect(slotText(item({ id: "p", state: "failed", error: "Nope" }))).toBe(
      "Nope",
    );
    expect(slotText(item({ id: "p", state: "failed" }))).toBe("Upload failed");
  });
});
