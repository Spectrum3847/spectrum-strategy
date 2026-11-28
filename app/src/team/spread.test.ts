import { describe, expect, it } from "vitest";
import { quantile, sampleSd, spreadOf, tied, trendOf } from "./spread";

const points = (values: number[]) =>
  values.map((value, i) => ({ key: `qm${i + 1}`, value }));

describe("sampleSd and quantile", () => {
  it("divides by n minus one and is null below two values", () => {
    expect(sampleSd([2, 4, 4, 4, 5, 5, 7, 9])).toBeCloseTo(2.138, 3);
    expect(sampleSd([5])).toBeNull();
  });

  it("interpolates linearly between sorted values", () => {
    expect(quantile([40, 10, 20, 30], 0.25)).toBe(17.5);
    expect(quantile([1, 2, 3, 4, 5], 0.5)).toBe(3);
    expect(quantile([7], 0.25)).toBe(7);
  });
});

const spreadPoints = (values: number[], broken: number[] = []) =>
  values.map((value, i) => ({
    key: `qm${i + 1}`,
    value,
    broken: broken.includes(i),
  }));

describe("spreadOf", () => {
  it("has nothing for no matches", () => {
    expect(spreadOf([])).toBeNull();
  });

  it("leaves out breakdown matches and says so", () => {
    const spread = spreadOf(spreadPoints([10, 20, 0], [2]));
    expect(spread).toMatchObject({ typical: 15, typicalN: 2 });
    expect(spread?.leftOut).toEqual([
      { key: "qm3", value: 0, reason: "breakdown" },
    ]);
  });

  it("uses every match, leaving none out, when fewer than two remain", () => {
    expect(spreadOf(spreadPoints([10, 0, 0], [1, 2]))).toMatchObject({
      typical: 10 / 3,
      typicalN: 3,
      leftOut: [],
    });
    expect(spreadOf(spreadPoints([8], [0]))).toMatchObject({
      typical: 8,
      typicalN: 1,
      leftOut: [],
    });
  });

  it("gives the standard error as sd over root n, null below two", () => {
    const spread = spreadOf(spreadPoints([10, 20, 30, 40]));
    expect(spread?.se).toBeCloseTo(6.455, 3);
    expect(spreadOf(spreadPoints([10]))?.se).toBeNull();
  });

  it("gives a floor and usual range only from four kept matches", () => {
    expect(spreadOf(spreadPoints([10, 20, 30]))).toMatchObject({
      floor: null,
      range: null,
    });
    expect(spreadOf(spreadPoints([10, 20, 30, 40]))).toMatchObject({
      floor: 17.5,
      range: [17.5, 32.5],
    });
    expect(spreadOf(spreadPoints([10, 20, 30, 40, 0], [4]))).toMatchObject({
      typical: 25,
      floor: 17.5,
    });
    expect(spreadOf(spreadPoints([10, 20, 30, 0], [3]))?.floor).toBeNull();
  });

  it("leaves out matches far below and far above the median, in play order", () => {
    const spread = spreadOf(spreadPoints([40, 42, 41, 43, 10, 41, 90]));
    expect(spread?.typical).toBeCloseTo(41.4, 5);
    expect(spread?.typicalN).toBe(5);
    expect(spread?.leftOut).toEqual([
      { key: "qm5", value: 10, reason: "low" },
      { key: "qm7", value: 90, reason: "high" },
    ]);
  });

  it("finds the median without the breakdown matches", () => {
    const spread = spreadOf(spreadPoints([40, 42, 41, 43, 41, 0, 90], [5]));
    expect(spread?.typical).toBeCloseTo(41.4, 5);
    expect(spread?.leftOut.map((m) => [m.key, m.reason])).toEqual([
      ["qm6", "breakdown"],
      ["qm7", "high"],
    ]);
  });

  it("keeps every match of a team that varies but has no outlier", () => {
    const spread = spreadOf(spreadPoints([30, 50, 40, 60, 20, 45, 35]));
    expect(spread?.leftOut).toEqual([]);
    expect(spread?.typicalN).toBe(7);
  });

  it("leaves nothing out when most matches are identical", () => {
    const spread = spreadOf(spreadPoints([20, 20, 20, 20, 20, 35]));
    expect(spread?.leftOut).toEqual([]);
    expect(spread?.typical).toBeCloseTo(135 / 6, 5);
  });

  it("calls an outlier only from five matches without a breakdown", () => {
    expect(spreadOf(spreadPoints([40, 42, 41, 10]))?.leftOut).toEqual([]);
    expect(spreadOf(spreadPoints([40, 42, 41, 43, 10]))?.leftOut).toEqual([
      { key: "qm5", value: 10, reason: "low" },
    ]);
  });
});

describe("trendOf", () => {
  it("needs six matches", () => {
    expect(trendOf(points([1, 2, 3, 4, 5]))).toBeNull();
    expect(trendOf(points([1, 2, 3, 4, 5, 6]))).not.toBeNull();
  });

  it("flags a change above twice its noise", () => {
    const trend = trendOf(points([10, 11, 10, 20, 21, 20]));
    expect(trend?.direction).toBe("improving");
    expect(trend?.delta).toBeCloseTo(10, 5);
    expect(trend?.laterKeys).toEqual(["qm4", "qm5", "qm6"]);
    expect(trendOf(points([20, 21, 20, 10, 11, 10]))?.direction).toBe(
      "declining",
    );
  });

  it("splits an odd count with the extra match in the second half", () => {
    const trend = trendOf(points([10, 10, 10, 11, 20, 21, 20]));
    expect(trend?.laterKeys).toEqual(["qm4", "qm5", "qm6", "qm7"]);
  });

  it("calls a change inside the noise steady", () => {
    expect(trendOf(points([10, 12, 9, 11, 10, 40]))?.direction).toBe("steady");
  });

  it("calls a steady change under two pieces a match steady", () => {
    expect(trendOf(points([10, 10, 10, 11, 11, 11]))?.direction).toBe("steady");
    expect(trendOf(points([10, 10, 10, 12, 12, 12]))?.direction).toBe(
      "improving",
    );
  });
});

describe("tied", () => {
  const a = { value: 100, se: 6 };

  it("is true when the gap is under the combined error", () => {
    expect(tied(a, { value: 107, se: 8 })).toBe(true);
    expect(tied(a, { value: 92, se: 8 })).toBe(true);
  });

  it("is false at or beyond the combined error", () => {
    expect(tied(a, { value: 110, se: 8 })).toBe(false);
    expect(tied(a, { value: 111, se: 8 })).toBe(false);
  });

  it("is false when either side has no error or no value", () => {
    expect(tied(a, { value: 100, se: null })).toBe(false);
    expect(tied(null, a)).toBe(false);
  });
});
