// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const enqueue = vi.hoisted(() => vi.fn());
const firestore = vi.hoisted(() => ({
  setDoc: vi.fn(),
  addDoc: vi.fn(),
  updateDoc: vi.fn(),
  deleteDoc: vi.fn(),
}));

vi.mock("../outbox/outbox", () => ({ enqueueWrite: enqueue }));
vi.mock("firebase/firestore", async (importActual) => ({
  ...(await importActual<typeof import("firebase/firestore")>()),
  ...firestore,
}));

import { savedEntries } from "../scout/local";
import { deliveryFrom, persistEntry } from "../scout/persist";
import { trainingEntries } from "./entries";
import { buildReplay } from "./replay";
import { isTraining, leaveTraining, startTraining } from "./session";

const doc = {
  id: "e1",
  tbaMatchKey: "2026test_qm1",
  teamNumber: 1111,
  alliance: "Red",
  fieldValues: { auto: 3 },
  authorDisplayName: "Scout A",
  updatedAt: "2026-01-01T00:00:00.000Z",
};
const saved = {
  id: "e1",
  matchId: "2026test_qm1",
  matchRef: "2026test_qm1",
  matchNumber: "1",
  team: 1111,
  tbaMatchKey: "2026test_qm1",
  station: "R1",
  createdAt: "2026-01-01T00:00:00.000Z",
  savedAt: "2026-01-01T00:00:00.000Z",
  qr: "payload",
};

beforeEach(() => {
  localStorage.clear();
  vi.clearAllMocks();
  startTraining("2026test", buildReplay([], []));
});

afterEach(() => leaveTraining());

describe("training save path", () => {
  it("never calls the outbox or Firestore", async () => {
    await persistEntry(doc, saved);
    expect(enqueue).not.toHaveBeenCalled();
    for (const fn of Object.values(firestore)) {
      expect(fn).not.toHaveBeenCalled();
    }
  });

  it("keeps the entry on the device, apart from live saves", async () => {
    await persistEntry(doc, saved);
    expect(savedEntries.get()).toEqual([]);
    expect(trainingEntries().saved).toHaveLength(1);
    expect(trainingEntries().entries[0]).toMatchObject({
      teamNumber: 1111,
      scoutName: "Scout A",
    });
  });

  it("writes only under the training prefix", async () => {
    await persistEntry(doc, saved);
    const keys = Object.keys(localStorage);
    expect(keys.length).toBeGreaterThan(0);
    expect(keys.every((k) => k.startsWith("ss.training."))).toBe(true);
  });

  it("drops the QR so a training entry cannot be scanned into live data", async () => {
    await persistEntry(doc, saved);
    expect(trainingEntries().saved[0]?.qr).toBeUndefined();
  });

  it("labels delivery as training", () => {
    expect(deliveryFrom([])("e1")).toEqual({
      status: "on-device",
      training: true,
    });
  });

  it("removes training data and leaves live data alone on leave", async () => {
    localStorage.setItem("ss.event.key", '"2027live"');
    savedEntries.add({ ...saved, id: "live1" });
    await persistEntry(doc, saved);
    leaveTraining();
    expect(isTraining()).toBe(false);
    expect(trainingEntries().saved).toEqual([]);
    expect(
      Object.keys(localStorage).some((k) => k.startsWith("ss.training.")),
    ).toBe(false);
    expect(localStorage.getItem("ss.event.key")).toBe('"2027live"');
    expect(savedEntries.get().map((e) => e.id)).toEqual(["live1"]);
  });
});

describe("live save path", () => {
  it("still goes through the outbox when training is off", async () => {
    leaveTraining();
    enqueue.mockResolvedValue("item");
    await persistEntry(doc, saved);
    expect(enqueue).toHaveBeenCalledWith(
      "scoutEntries/e1",
      doc,
      "Team 1111, match 1",
    );
    expect(savedEntries.get().map((e) => e.id)).toContain("e1");
  });
});
