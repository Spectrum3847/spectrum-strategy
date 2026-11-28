import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { parseConfig } from "../scout/config";
import { computeStats, groupByMatch, type StatInput } from "./stats";
import { lastMatches, windowNote } from "./window";

const config = parseConfig(bundled);
const entry = (id: string, key: string, fuel: number): StatInput => ({
  id,
  matchKey: key,
  fieldValues: { teleopFuelScored: fuel },
});
const key = (n: number) => `2027test_qm${n}`;
const inputs = [
  entry("a", key(5), 10),
  entry("b", key(1), 20),
  entry("c", key(1), 40),
  entry("d", key(9), 50),
  entry("e", key(3), 60),
];

describe("lastMatches", () => {
  it("keeps everything for All", () => {
    expect(lastMatches(inputs, null)).toBe(inputs);
  });

  it("keeps the newest matches by play order, not arrival order", () => {
    const kept = lastMatches(inputs, 2);
    expect(groupByMatch(kept).map((g) => g.key)).toEqual([key(5), key(9)]);
  });

  it("keeps every scout of a kept match", () => {
    const kept = lastMatches(inputs, 4);
    expect(kept.map((i) => i.id).sort()).toEqual(["a", "b", "c", "d", "e"]);
  });

  it("feeds the per-match collapse the kept matches only", () => {
    const stats = computeStats(config, lastMatches(inputs, 3));
    const fuel = stats.rows.find((r) => r.code === "teleopFuelScored");
    expect(stats.matches).toBe(3);
    expect(fuel?.n).toBe(3);
    expect(fuel?.mean).toBe(40);
    expect(stats.series.map((p) => p.key)).toEqual([key(3), key(5), key(9)]);
  });

  it("returns everything when there are fewer matches than asked", () => {
    expect(lastMatches(inputs, 6)).toBe(inputs);
  });
});

describe("windowNote", () => {
  it("says what is shown", () => {
    expect(windowNote(null, 7)).toBe("Showing all 7 scouted matches.");
    expect(windowNote(3, 2)).toBe("Showing all 2 scouted matches.");
    expect(windowNote(3, 7)).toContain("last 3 of 7");
    expect(windowNote(3, 0)).toBe("");
  });
});
