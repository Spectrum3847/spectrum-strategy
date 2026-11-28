// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { emptyBoard, setCell } from "./board";
import {
  blankCache,
  cacheKey,
  clearLegacy,
  legacyKey,
  loadCache,
  loadLegacy,
  saveCache,
} from "./storage";

const cell = { grid: "meeting" as const, row: 0, column: 0 };

beforeEach(() => {
  localStorage.clear();
  vi.restoreAllMocks();
});

describe("board cache", () => {
  it("keeps a copy per event under ss.playoff.cache.", () => {
    const board = setCell(emptyBoard(), cell, "1111");
    expect(
      saveCache("2027a", { board, ms: 5, by: "Scout A", pending: true }),
    ).toBe(true);
    expect(cacheKey("2027a")).toBe("ss.playoff.cache.2027a");
    expect(loadCache("2027a")).toEqual({
      board,
      ms: 5,
      by: "Scout A",
      pending: true,
    });
    expect(loadCache("2027b")).toBeNull();
  });

  it("reads corrupt storage as no copy", () => {
    localStorage.setItem("ss.playoff.cache.2027a", "{not json");
    expect(loadCache("2027a")).toBeNull();
  });

  it("says so when the device will not keep it", () => {
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("full");
    });
    expect(saveCache("2027a", blankCache())).toBe(false);
  });

  it("keeps nothing without an event", () => {
    expect(saveCache("", blankCache())).toBe(false);
    expect(loadCache("")).toBeNull();
  });
});

describe("board saved before boards synced", () => {
  it("reads and clears the old per-event key", () => {
    localStorage.setItem(
      legacyKey("2027a"),
      JSON.stringify({ version: 1, meeting: { "0,0": "1111" } }),
    );
    expect(loadLegacy("2027a")?.meeting).toEqual({ "0,0": "1111" });
    clearLegacy("2027a");
    expect(loadLegacy("2027a")).toBeNull();
  });

  it("reads corrupt storage as nothing", () => {
    localStorage.setItem(legacyKey("2027a"), "{not json");
    expect(loadLegacy("2027a")).toBeNull();
  });
});
