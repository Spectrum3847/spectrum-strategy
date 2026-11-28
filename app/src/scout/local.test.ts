// @vitest-environment jsdom
import { beforeEach, describe, expect, it } from "vitest";
import {
  draftStore,
  matchRefOf,
  type SavedEntry,
  savedEntries,
  stationStore,
} from "./local";

beforeEach(() => {
  localStorage.clear();
  savedEntries.reload();
});

const entry = (id: string, over: Partial<SavedEntry> = {}): SavedEntry => ({
  id,
  matchId: "2027test_qm1",
  matchRef: "2027test_qm1",
  matchNumber: "1",
  team: 111,
  tbaMatchKey: "2027test_qm1",
  station: "R1",
  createdAt: "2027-03-05T18:00:00.000Z",
  savedAt: "2027-03-05T18:00:00.000Z",
  ...over,
});

describe("station", () => {
  it("is remembered on this device", () => {
    expect(stationStore.get()).toBeNull();
    stationStore.set("B2");
    expect(stationStore.get()).toBe("B2");
  });
});

describe("saved entries", () => {
  it("keeps the newest first and replaces one with the same id", () => {
    savedEntries.add(entry("a"));
    savedEntries.add(entry("b", { team: 222 }));
    savedEntries.add(entry("a", { team: 333 }));
    expect(savedEntries.get().map((e) => e.id)).toEqual(["a", "b"]);
    expect(savedEntries.find("2027test_qm1", 333)?.id).toBe("a");
  });

  it("survives a reload", () => {
    savedEntries.add(entry("a"));
    savedEntries.reload();
    expect(savedEntries.get()).toHaveLength(1);
  });

  it("groups by TBA key, else event and typed number", () => {
    expect(matchRefOf("2027test_qm1", "2027test", "1")).toBe("2027test_qm1");
    expect(matchRefOf(null, "2027test", " 9 ")).toBe("typed:2027test:9");
  });
});

describe("draft", () => {
  it("restores only for the same form shape", () => {
    draftStore.set("shape-1", { a: 1 });
    expect(draftStore.get("shape-1")).toEqual({ a: 1 });
    expect(draftStore.get("shape-2")).toBeNull();
    draftStore.clear();
    expect(draftStore.get("shape-1")).toBeNull();
  });
});
