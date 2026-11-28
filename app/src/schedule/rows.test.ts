import { describe, expect, it } from "vitest";
import type { ScheduledMatch } from "../scout/schedule";
import {
  ourOutcome,
  ourSide,
  resultText,
  splitSchedule,
  winnerOf,
} from "./rows";

const qm = (
  n: number,
  scores?: [number, number],
  red = [1111, 2222, 3333],
): ScheduledMatch => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red,
  blue: [4444, 5555, 6666],
  ...(scores ? { redScore: scores[0], blueScore: scores[1] } : {}),
});

describe("splitSchedule", () => {
  const schedule = [
    qm(3),
    qm(1, [50, 40]),
    qm(2, [30, 30], [7777, 8888, 9999]),
    {
      key: "2027test_sf1m1",
      compLevel: "sf",
      matchNumber: 1,
      red: [1111],
      blue: [4444],
    },
  ];

  it("lists upcoming in play order and played newest first", () => {
    const rows = splitSchedule(schedule, null, false);
    expect(rows.upcoming.map((m) => m.key)).toEqual([
      "2027test_qm3",
      "2027test_sf1m1",
    ]);
    expect(rows.played.map((m) => m.key)).toEqual([
      "2027test_qm2",
      "2027test_qm1",
    ]);
  });

  it("keeps only our matches when asked", () => {
    const rows = splitSchedule(schedule, 1111, true);
    expect(rows.upcoming.map((m) => m.key)).toEqual([
      "2027test_qm3",
      "2027test_sf1m1",
    ]);
    expect(rows.played.map((m) => m.key)).toEqual(["2027test_qm1"]);
  });

  it("does not filter without a team number", () => {
    expect(splitSchedule(schedule, null, true).played).toHaveLength(2);
  });

  it("treats a schedule with no scores as all upcoming", () => {
    const rows = splitSchedule([qm(1), qm(2)], null, false);
    expect(rows.upcoming).toHaveLength(2);
    expect(rows.played).toHaveLength(0);
  });

  it("does not reorder the input", () => {
    const input = [qm(2), qm(1)];
    splitSchedule(input, null, false);
    expect(input.map((m) => m.matchNumber)).toEqual([2, 1]);
  });
});

describe("results", () => {
  it("names the winner", () => {
    expect(winnerOf(qm(1, [50, 40]))).toBe("Red");
    expect(winnerOf(qm(1, [40, 50]))).toBe("Blue");
    expect(winnerOf(qm(1, [40, 40]))).toBe("Tie");
    expect(winnerOf(qm(1))).toBeNull();
    expect(winnerOf(qm(1, [-1, -1]))).toBeNull();
  });

  it("writes the result line", () => {
    expect(resultText(qm(1, [50, 40]))).toBe("Red won");
    expect(resultText(qm(1, [40, 40]))).toBe("Tie");
    expect(resultText(qm(1))).toBeNull();
  });

  it("finds our side and how we did", () => {
    expect(ourSide(qm(1), 1111)).toBe("Red");
    expect(ourSide(qm(1), 5555)).toBe("Blue");
    expect(ourSide(qm(1), 9999)).toBeNull();
    expect(ourSide(qm(1), null)).toBeNull();
    expect(ourOutcome(qm(1, [50, 40]), 1111)).toBe("won");
    expect(ourOutcome(qm(1, [50, 40]), 4444)).toBe("lost");
    expect(ourOutcome(qm(1, [40, 40]), 4444)).toBe("tied");
    expect(ourOutcome(qm(1), 1111)).toBeNull();
    expect(ourOutcome(qm(1, [50, 40]), 9999)).toBeNull();
  });
});
