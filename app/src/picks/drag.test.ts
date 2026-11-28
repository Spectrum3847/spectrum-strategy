import { describe, expect, it } from "vitest";
import { insertIndex } from "./drag";

describe("insertIndex", () => {
  const middles = [100, 200, 300];

  it("lands before the first row whose middle is below the pointer", () => {
    expect(insertIndex(middles, 50)).toBe(0);
    expect(insertIndex(middles, 150)).toBe(1);
    expect(insertIndex(middles, 250)).toBe(2);
  });

  it("lands at the end below every row, and in an empty column", () => {
    expect(insertIndex(middles, 400)).toBe(3);
    expect(insertIndex([], 10)).toBe(0);
  });
});
