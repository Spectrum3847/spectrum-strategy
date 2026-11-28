import { describe, expect, it } from "vitest";
import { quantile } from "./AnalysisPage";

describe("analysis quantiles", () => {
  it("interpolates quartiles and handles a single match", () => {
    expect(quantile([10, 20, 30, 40], 0.25)).toBe(17.5);
    expect(quantile([10, 20, 30, 40], 0.5)).toBe(25);
    expect(quantile([12], 0.75)).toBe(12);
  });
});
