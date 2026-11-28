import { describe, expect, it } from "vitest";
import { parseEpa, parseForecasts } from "./outside";

describe("parseEpa", () => {
  it("reads the total of each team, as a number or as { mean }", () => {
    expect(
      parseEpa([
        { team: 1111, epa: { total_points: 42.5 } },
        { team: 2222, epa: { total_points: { mean: 30, sd: 4 } } },
      ]),
    ).toEqual({ 1111: 42.5, 2222: 30 });
  });

  it("leaves out a team with no total and ignores junk", () => {
    expect(
      parseEpa([
        { team: 1111, epa: {} },
        { team: 2222 },
        { team: "x", epa: { total_points: 3 } },
        null,
      ]),
    ).toEqual({});
    expect(parseEpa({})).toEqual({});
    expect(parseEpa([])).toEqual({});
  });
});

describe("parseForecasts", () => {
  const raw = {
    match_predictions: {
      qual: {
        "2027test_qm1": {
          red: { score: 60.2 },
          blue: { score: 55.1 },
          winning_alliance: "red",
          prob: 0.7,
        },
        "2027test_qm2": {
          red: { score: 50 },
          blue: { score: 58 },
          winning_alliance: "blue",
          prob: 65,
        },
        "2027test_qm3": { red: {}, blue: {}, winning_alliance: "", prob: 0 },
      },
      playoff: {
        "2027test_sf1m1": {
          red: { score: 70 },
          blue: { score: 70 },
          winning_alliance: "red",
          prob: 0.5,
        },
      },
    },
  };

  it("merges qualification and playoff predictions by match key", () => {
    const out = parseForecasts(raw);
    expect(Object.keys(out).sort()).toEqual([
      "2027test_qm1",
      "2027test_qm2",
      "2027test_qm3",
      "2027test_sf1m1",
    ]);
  });

  it("reads confidence as red's chance whichever alliance is called", () => {
    const out = parseForecasts(raw);
    expect(out["2027test_qm1"]?.redWin).toBeCloseTo(0.7);
    expect(out["2027test_qm2"]?.redWin).toBeCloseTo(0.35);
    expect(out["2027test_qm2"]?.blueScore).toBe(58);
  });

  it("calls no winner an even match", () => {
    expect(parseForecasts(raw)["2027test_qm3"]?.redWin).toBe(0.5);
  });

  it("is empty before TBA has predictions", () => {
    expect(parseForecasts({})).toEqual({});
    expect(parseForecasts(null)).toEqual({});
  });
});
