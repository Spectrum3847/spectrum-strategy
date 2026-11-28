import { describe, expect, it } from "vitest";
import type { ScoutShifts } from "../scout/credit";
import type { ScheduledMatch } from "../scout/schedule";
import { buildNow, lastPlayedQual, nextShift } from "./summary";

const qm = (
  n: number,
  red: number[],
  blue: number[],
  played = false,
): ScheduledMatch => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red,
  blue,
  redScore: played ? 30 : -1,
  blueScore: played ? 20 : -1,
});

const other = [4444, 5555, 6666];
const mates = [2222, 3333];

describe("buildNow", () => {
  it("has no schedule", () => {
    expect(buildNow([], 1111)).toEqual({ state: "no-schedule" });
  });

  it("says when the team is not on the schedule", () => {
    expect(buildNow([qm(1, [7, 8, 9], other)], 1111)).toEqual({
      state: "not-on-schedule",
    });
  });

  it("finds our next match, our side, and the matches still to play", () => {
    const schedule = [
      qm(1, [1111, ...mates], other, true),
      qm(2, [7, 8, 9], [10, 11, 12]),
      qm(3, [10, 11, 12], [1111, ...mates]),
      qm(4, [1111, ...mates], other),
    ];
    const summary = buildNow(schedule, 1111);
    if (summary.state !== "ready") throw new Error("not ready");
    expect(summary.next?.label).toBe("Q3");
    expect(summary.next?.alliance).toBe("Blue");
    expect(summary.next?.ourSide).toEqual([1111, 2222, 3333]);
    expect(summary.next?.opponents).toEqual([10, 11, 12]);
    expect(summary.next?.away).toBe(1);
    expect(summary.later.map((m) => m.label)).toEqual(["Q4"]);
    expect(summary.later[0]?.away).toBe(2);
    expect(summary.playedCount).toBe(1);
    expect(summary.totalCount).toBe(3);
    expect(summary.scheduleDone).toBe(false);
  });

  it("counts a match in play order, not array order", () => {
    const summary = buildNow(
      [qm(3, [1111, ...mates], other), qm(1, [7, 8, 9], [10, 11, 12])],
      1111,
    );
    if (summary.state !== "ready") throw new Error("not ready");
    expect(summary.next?.away).toBe(1);
  });

  it("has no next match once ours are played", () => {
    const summary = buildNow(
      [qm(1, [1111, ...mates], other, true), qm(2, [7, 8, 9], [10, 11, 12])],
      1111,
    );
    if (summary.state !== "ready") throw new Error("not ready");
    expect(summary.next).toBeNull();
    expect(summary.playedCount).toBe(1);
    expect(summary.scheduleDone).toBe(false);
  });

  it("is done only when every match is played and the finals are on it", () => {
    const final: ScheduledMatch = {
      ...qm(1, [1111, ...mates], other, true),
      key: "2027test_f1m1",
      compLevel: "f",
    };
    const done = buildNow([qm(1, [1111, ...mates], other, true), final], 1111);
    if (done.state !== "ready") throw new Error("not ready");
    expect(done.scheduleDone).toBe(true);
    const noFinals = buildNow([qm(1, [1111, ...mates], other, true)], 1111);
    if (noFinals.state !== "ready") throw new Error("not ready");
    expect(noFinals.scheduleDone).toBe(false);
  });
});

describe("lastPlayedQual", () => {
  it("is the highest played qualification number", () => {
    expect(
      lastPlayedQual([
        qm(1, [1], [2], true),
        qm(3, [1], [2], true),
        qm(2, [1], [2]),
      ]),
    ).toBe(3);
    expect(lastPlayedQual([qm(1, [1], [2])])).toBeNull();
  });
});

const shifts = (blocks: ScoutShifts["rotations"][number]["blocks"]) =>
  ({
    roster: [{ uid: "scout-a", name: "Scout A" }],
    rotations: [{ uid: "scout-a", blocks }],
    colors: new Map(),
    texts: new Map(),
    matchCount: 24,
    authorUid: "lead",
    authorDisplayName: "Lead",
  }) satisfies ScoutShifts;

describe("nextShift", () => {
  const blocks = [
    { startMatch: 10, endMatch: 14, station: "B2" },
    { startMatch: 1, endMatch: 5, station: "R1" },
  ];

  it("reports no grid and an unscheduled scout", () => {
    expect(nextShift(null, ["scout-a"], null)).toEqual({ status: "no-grid" });
    expect(nextShift(shifts(blocks), ["scout-z"], null)).toEqual({
      status: "not-scheduled",
    });
  });

  it("is on duty when the next match is inside a block", () => {
    const shift = nextShift(shifts(blocks), ["scout-a"], 2);
    expect(shift).toMatchObject({ status: "next", away: 0 });
    expect(shift.status === "next" && shift.block.station).toBe("R1");
  });

  it("counts matches until the next block starts", () => {
    const shift = nextShift(shifts(blocks), ["scout-a"], 5);
    expect(shift).toMatchObject({ status: "next", away: 4 });
    expect(shift.status === "next" && shift.block.startMatch).toBe(10);
  });

  it("starts at match 1 before anything is played", () => {
    expect(nextShift(shifts(blocks), ["scout-a"], null)).toMatchObject({
      status: "next",
      away: 0,
    });
  });

  it("is done after the last block", () => {
    expect(nextShift(shifts(blocks), ["scout-a"], 14)).toEqual({
      status: "done",
    });
  });

  it("finds a scout by a linked account's uid", () => {
    expect(nextShift(shifts(blocks), ["secondary", "scout-a"], 0).status).toBe(
      "next",
    );
  });
});
