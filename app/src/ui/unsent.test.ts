import { describe, expect, it } from "vitest";
import { unsentCounts, unsentLines, unsentTotal } from "./unsent";

describe("unsentCounts", () => {
  it("counts items that are not in the database yet", () => {
    const counts = unsentCounts([
      { status: "on-device" },
      { status: "sending" },
      { status: "in-database" },
      { status: "refused" },
    ]);
    expect(counts).toEqual({ pending: 2, refused: 1 });
    expect(unsentTotal(counts)).toBe(3);
  });

  it("counts nothing for an empty outbox", () => {
    expect(unsentCounts([])).toEqual({ pending: 0, refused: 0 });
  });
});

describe("unsentLines", () => {
  it("says nothing when nothing is unsent", () => {
    expect(unsentLines({ pending: 0, refused: 0 }, true)).toEqual([]);
  });

  it("names the count and adds the offline note only when offline", () => {
    expect(unsentLines({ pending: 1, refused: 0 }, true)).toEqual([
      "1 entry is saved on this device and not in the database yet.",
    ]);
    expect(unsentLines({ pending: 3, refused: 0 }, false)).toEqual([
      "3 entries are saved on this device and not in the database yet. They send when this device is back online.",
    ]);
  });

  it("adds a line for refused entries", () => {
    expect(unsentLines({ pending: 0, refused: 2 }, true)).toEqual([
      "2 entries were refused by the database.",
    ]);
  });
});
