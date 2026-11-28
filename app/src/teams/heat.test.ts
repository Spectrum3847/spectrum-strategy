import { describe, expect, it } from "vitest";
import { heatLevels } from "./heat";

describe("heatLevels", () => {
  it("gives the best fifth the top level and the worst none", () => {
    const levels = heatLevels([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], true);
    expect(levels[0]).toBe(0);
    expect(levels[9]).toBe(4);
    expect(levels).toEqual([...levels].sort((a, b) => a - b));
  });

  it("flips for a lower-is-better column", () => {
    const levels = heatLevels([1, 2, 3, 4, 5], false);
    expect(levels[0]).toBe(4);
    expect(levels[4]).toBe(0);
  });

  it("leaves a missing value without a tint", () => {
    const levels = heatLevels([1, null, 5, 9, 12], true);
    expect(levels[1]).toBe(0);
    expect(levels[4]).toBe(4);
  });

  it("colors nothing for fewer than four teams or a flat column", () => {
    expect(heatLevels([1, 5, 9], true)).toEqual([0, 0, 0]);
    expect(heatLevels([5, 5, 5, 5, 5], true)).toEqual([0, 0, 0, 0, 0]);
  });

  it("gives equal values one level", () => {
    const levels = heatLevels([1, 5, 5, 9, 12], true);
    expect(levels[1]).toBe(levels[2]);
  });
});
