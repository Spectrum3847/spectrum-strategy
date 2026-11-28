import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { parseConfig } from "../scout/config";
import { entryMatchKey, phaseStats, type StatInput } from "./stats";

const config = parseConfig(bundled);

const input = (
  id: string,
  matchKey: string,
  values: Record<string, unknown>,
): StatInput => ({ id, matchKey, fieldValues: values });

describe("phaseStats", () => {
  it("sums the counters of each phase per match, then summarizes", () => {
    const stats = phaseStats(config, [
      input("a", "m1", { autoFuelScored: 2, teleopFuelScored: 8 }),
      input("b", "m2", { autoFuelScored: 4, teleopFuelScored: 12 }),
    ]);
    expect(stats.auto?.mean).toBe(3);
    expect(stats.teleop?.mean).toBe(10);
    expect(stats.teleop?.max).toBe(12);
    expect(stats.auto?.n).toBe(2);
  });

  it("counts several scouts of one match once, averaged", () => {
    const stats = phaseStats(config, [
      input("a", "m1", { autoFuelScored: 2 }),
      input("b", "m1", { autoFuelScored: 4 }),
    ]);
    expect(stats.auto?.n).toBe(1);
    expect(stats.auto?.mean).toBe(3);
  });

  it("is empty with no entries, and a phase with no value stays empty", () => {
    expect(phaseStats(config, [])).toEqual({ auto: null, teleop: null });
    const stats = phaseStats(config, [input("a", "m1", { autoFuelScored: 1 })]);
    expect(stats.auto?.mean).toBe(1);
    expect(stats.teleop).toBeNull();
  });

  it("leaves out ranges such as scoring accuracy", () => {
    const stats = phaseStats(config, [
      input("a", "m1", { teleopFuelScored: 5, scoringEff: 90 }),
    ]);
    expect(stats.teleop?.mean).toBe(5);
  });
});

describe("entryMatchKey", () => {
  const base = { id: "e1", tbaMatchKey: null, fieldValues: {} };

  it("prefers the TBA key, lower case", () => {
    expect(entryMatchKey({ ...base, tbaMatchKey: "2027test_QM3" })).toBe(
      "2027test_qm3",
    );
  });

  it("falls back to the typed match number, then the entry", () => {
    expect(
      entryMatchKey({ ...base, fieldValues: { matchNumber: " 7 " } }),
    ).toBe("typed:7");
    expect(entryMatchKey(base)).toBe("e1");
  });
});
