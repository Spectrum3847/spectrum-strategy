import { describe, expect, it } from "vitest";
import pitDefault from "../../../assets/pit_scout_config_default.json";
import bundled from "../../../assets/scout_config_default.json";
import { parseEventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import {
  buildFacts,
  noFacts,
  statLine,
  type TeamFacts,
  tiedWithAbove,
} from "./facts";

const facts = (typical: number | null, se: number | null): TeamFacts => ({
  ...noFacts,
  typical,
  se,
  n: 5,
});

describe("tiedWithAbove", () => {
  const all = new Map([
    [1, facts(100, 6)],
    [2, facts(104, 6)],
    [3, facts(60, 5)],
    [4, facts(63, 5)],
    [5, facts(null, null)],
    [6, facts(63, null)],
  ]);

  it("names the team above when the scores differ by less than their ± together", () => {
    expect(tiedWithAbove([1, 2, 3, 4], all)).toEqual(
      new Map([
        [2, 1],
        [4, 3],
      ]),
    );
  });

  it("compares each team with the one directly above it only", () => {
    expect(tiedWithAbove([1, 3, 2], all)).toEqual(new Map());
  });

  it("skips an unscouted team or one with no ±, and the first row", () => {
    expect(tiedWithAbove([4, 5, 6], all)).toEqual(new Map());
    expect(tiedWithAbove([1], all)).toEqual(new Map());
    expect(tiedWithAbove([], all)).toEqual(new Map());
  });

  it("knows no team that has no facts", () => {
    expect(tiedWithAbove([1, 9], all)).toEqual(new Map());
  });
});

describe("statLine", () => {
  it("shows the score with its ± and the matches behind it", () => {
    expect(statLine({ ...facts(25, 6.455), rank: 3 })).toBe(
      "Score 25 ±6.5 (n=5) · Rank 3",
    );
  });

  it("leaves the ± out below two matches and says when nobody scouted", () => {
    expect(statLine(facts(25, null))).toBe("Score 25 (n=5)");
    expect(statLine(noFacts)).toBe("Not scouted");
  });
});

describe("buildFacts", () => {
  it("shows the typical total on the row and adds up plain averages for fit", () => {
    const entries = [40, 42, 41, 43, 41, 90].map((teleop, i) =>
      parseEventEntry(`e${i}`, {
        teamNumber: 1111,
        tbaMatchKey: `2027test_qm${i + 1}`,
        fieldValues: { autoFuelScored: 6, teleopFuelScored: teleop },
      }),
    );
    const found = buildFacts({
      config: parseConfig(bundled),
      pitConfig: parseConfig(pitDefault),
      entries,
      pit: [],
      rankings: [],
      epa: null,
    }).get(1111);
    expect(found?.typical).toBeCloseTo(47.4, 5);
    expect(found?.n).toBe(5);
    expect(found?.mean).toBeCloseTo(55.5, 5);
    expect(found?.auto).toBe(6);
  });
});
