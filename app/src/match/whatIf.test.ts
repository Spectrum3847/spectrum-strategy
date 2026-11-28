import { describe, expect, it } from "vitest";
import type { EventEntry } from "../data/parse";
import { normalCdf, readyTeams, scoutedWinChance } from "./whatIf";

const entry = (team: number, n: number, auto: number, teleop: number) =>
  ({
    id: `${team}-${n}`,
    teamNumber: team,
    alliance: "Red",
    tbaMatchKey: `2027test_qm${n}`,
    scoutName: "Scout A",
    updatedAt: "2027-03-01T10:00:00.000Z",
    fieldValues: { autoFuelScored: auto, teleopFuelScored: teleop },
  }) satisfies EventEntry;

const team = (t: number, auto: number, teleop: number) =>
  [auto, auto + 1, auto - 1].map((a, i) =>
    entry(t, i + 1, a, teleop + (i - 1) * 2),
  );

describe("readyTeams", () => {
  it("needs six valid team numbers", () => {
    expect(readyTeams(["1", "2", "3", "4", "5", "6"])).toEqual({
      red: [1, 2, 3],
      blue: [4, 5, 6],
    });
    expect(readyTeams(["1", "2", "3", "4", "5", ""])).toBeNull();
    expect(readyTeams(["1", "2", "3", "4", "5", "x"])).toBeNull();
    expect(readyTeams(["frc1111", "2", "3", "4", "5", "6"])?.red[0]).toBe(1111);
  });
});

describe("normalCdf", () => {
  it("is 0.5 at zero and symmetric", () => {
    expect(normalCdf(0)).toBeCloseTo(0.5, 6);
    expect(normalCdf(1.5) + normalCdf(-1.5)).toBeCloseTo(1, 6);
    expect(normalCdf(1.96)).toBeCloseTo(0.975, 3);
  });
});

describe("scoutedWinChance", () => {
  const strong = [1, 2, 3].flatMap((t) => team(t, 10, 40));
  const weak = [4, 5, 6].flatMap((t) => team(t, 2, 5));

  it("favours the alliance that scores more", () => {
    const chance = scoutedWinChance([1, 2, 3], [4, 5, 6], [...strong, ...weak]);
    expect(chance.missing).toEqual([]);
    expect(chance.red).toBe(0.99);
    expect(
      scoutedWinChance([4, 5, 6], [1, 2, 3], [...strong, ...weak]).red,
    ).toBe(0.01);
  });

  it("names the teams without three entries instead of guessing", () => {
    const chance = scoutedWinChance([1, 2, 3], [4, 5, 7], [...strong, ...weak]);
    expect(chance.red).toBeNull();
    expect(chance.missing).toEqual([7]);
  });
});
