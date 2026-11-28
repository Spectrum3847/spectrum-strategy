import { describe, expect, it } from "vitest";
import type { EventEntry } from "../data/parse";
import type { EventMatch } from "../data/tbaEvent";
import {
  buildCheck,
  type Called,
  calledByScouting,
  calledByTba,
  minBand,
  verdict,
} from "./predictionCheck";

const called = (
  n: number,
  redWin: number,
  scores: [number, number],
  predicted: [number, number] | null = [50, 40],
): Called => ({
  key: `2027test_qm${n}`,
  red: [1111, 2222, 3333],
  blue: [4444, 5555, 6666],
  redScore: scores[0],
  blueScore: scores[1],
  redWin,
  predRed: predicted?.[0] ?? null,
  predBlue: predicted?.[1] ?? null,
});

describe("buildCheck", () => {
  it("counts the favourite's wins, ties as half", () => {
    const check = buildCheck(
      [
        called(1, 0.8, [60, 40]),
        called(2, 0.7, [40, 60]),
        called(3, 0.3, [30, 50]),
        called(4, 0.6, [50, 50]),
      ],
      null,
    );
    expect(check.n).toBe(4);
    expect(check.right).toBe(2.5);
    expect(check.enough).toBe(false);
    expect(check.rows[2]).toMatchObject({ favourite: "blue", right: 1 });
    expect(check.rows[3]?.right).toBe(0.5);
  });

  it("measures the score miss and its lean", () => {
    const check = buildCheck([called(1, 0.8, [60, 30])], null);
    expect(check.error).toBe((10 + 10) / 2);
    expect(check.lean).toBe((-10 + 10) / 2);
    expect(check.rows[0]?.miss).toBe(10);
  });

  it("has no score miss for a source without scores", () => {
    const check = buildCheck([called(1, 0.8, [60, 30], null)], null);
    expect(check.error).toBeNull();
    expect(check.misses).toEqual([]);
  });

  it("groups by the chance given and reads whether it held", () => {
    const rows = [
      ...Array.from({ length: 9 }, (_, i) => called(i + 1, 0.95, [60, 40])),
      called(10, 0.95, [40, 60]),
    ];
    const check = buildCheck(rows, null);
    const band = check.bands.find((b) => b.label === "90-100%");
    expect(band).toBeDefined();
    if (!band) return;
    expect(band.n).toBe(10);
    expect(band.won).toBeCloseTo(0.9);
    expect(check.enough).toBe(true);
    expect(verdict(band)).toBe("about right");
  });

  it("lists our matches newest first and the five biggest misses", () => {
    const rows = [
      called(1, 0.6, [100, 40], [50, 40]),
      called(2, 0.6, [55, 40], [50, 40]),
      called(3, 0.6, [70, 40], [50, 40]),
      called(4, 0.6, [90, 40], [50, 40]),
      called(5, 0.6, [80, 40], [50, 40]),
      called(6, 0.6, [60, 40], [50, 40]),
    ];
    const check = buildCheck(rows, 4444);
    expect(check.ours.map((r) => r.key)[0]).toBe("2027test_qm6");
    expect(check.misses.map((r) => r.key)).toEqual([
      "2027test_qm1",
      "2027test_qm4",
      "2027test_qm5",
      "2027test_qm3",
      "2027test_qm6",
    ]);
    expect(buildCheck(rows, null).ours).toEqual([]);
  });
});

describe("verdict", () => {
  const band = (n: number, said: number, won: number) => ({
    label: "x",
    n,
    said,
    won,
  });

  it("needs enough matches in the band", () => {
    expect(verdict(band(minBand - 1, 0.9, 0.1))).toBe("too few to tell");
  });

  it("says too confident or too cautious past 15 points", () => {
    expect(verdict(band(20, 0.9, 0.7))).toBe("too confident");
    expect(verdict(band(20, 0.6, 0.8))).toBe("too cautious");
    expect(verdict(band(20, 0.8, 0.72))).toBe("about right");
  });
});

const match = (
  n: number,
  scores: [number, number] | null,
  red = [1111, 2222, 3333],
): EventMatch => ({
  key: `2027test_qm${n}`,
  level: "qm",
  red,
  blue: [4444, 5555, 6666],
  redScore: scores?.[0] ?? null,
  blueScore: scores?.[1] ?? null,
  winner: null,
});

describe("calledByTba", () => {
  it("reads the forecast of each played match, scores or not", () => {
    const out = calledByTba(
      [match(1, [60, 40]), match(2, [30, 50]), match(3, null)],
      {
        "2027test_qm1": { redScore: 55, blueScore: 45, redWin: 0.7 },
        "2027test_qm2": { redScore: 0, blueScore: 0, redWin: 0.5 },
        "2027test_qm3": { redScore: 50, blueScore: 50, redWin: 0.5 },
      },
    );
    expect(out.map((c) => c.key)).toEqual(["2027test_qm1", "2027test_qm2"]);
    expect(out[0]).toMatchObject({ predRed: 55, redWin: 0.7 });
    expect(out[1]).toMatchObject({ predRed: null, predBlue: null });
  });

  it("is empty without forecasts", () => {
    expect(calledByTba([match(1, [60, 40])], null)).toEqual([]);
  });
});

describe("calledByScouting", () => {
  const entry = (
    team: number,
    n: number,
    auto: number,
    teleop: number,
  ): EventEntry => ({
    id: `${team}-${n}`,
    teamNumber: team,
    alliance: "Red",
    tbaMatchKey: `2027test_qm${n}`,
    scoutName: "Scout A",
    updatedAt: "2027-03-01T10:00:00.000Z",
    fieldValues: { autoFuelScored: auto, teleopFuelScored: teleop },
  });
  const crew = (
    teams: number[],
    auto: number,
    teleop: number,
    from: number[],
  ) =>
    teams.flatMap((t) =>
      from.map((n, i) => entry(t, n, auto + (i % 2), teleop + i)),
    );
  const strong = [1111, 2222, 3333];
  const weak = [4444, 5555, 6666];

  it("uses only the matches before each one", () => {
    const entries = [
      ...crew(strong, 10, 40, [1, 2, 3]),
      ...crew(weak, 2, 5, [1, 2, 3]),
      ...crew(strong, 0, 0, [4]),
      ...crew(weak, 90, 90, [4]),
    ];
    const out = calledByScouting([match(4, [60, 30])], entries);
    expect(out).toHaveLength(1);
    expect(out[0]?.redWin).toBeGreaterThan(0.9);
    expect(out[0]).toMatchObject({ predRed: null, predBlue: null });
  });

  it("skips a match whose robots lack three earlier matches", () => {
    const entries = crew([...strong, ...weak], 5, 20, [1, 2]);
    expect(calledByScouting([match(3, [60, 30])], entries)).toEqual([]);
  });
});
