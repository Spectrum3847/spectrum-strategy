import { describe, expect, it } from "vitest";
import {
  acceptedTrades,
  applyTrades,
  parseShifts,
  parseTradeDocs,
} from "../scout/credit";
import type { RemoteEntry, ScheduledMatch } from "../scout/schedule";
import { awayText, myBlocks, playedThrough, rangeText } from "./mine";

const quals: ScheduledMatch[] = [1, 2, 3, 4].map((n) => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red: [],
  blue: [],
}));

const entry = (id: string, key: string, robot: string): RemoteEntry => ({
  id,
  tbaMatchKey: key,
  fieldValues: { robot },
});

const scored = (played: number): ScheduledMatch[] =>
  quals.map((m) => {
    const done = m.matchNumber <= played;
    return { ...m, redScore: done ? 50 : -1, blueScore: done ? 40 : -1 };
  });

describe("playedThrough", () => {
  it("is the last played qual when the schedule has scores", () => {
    expect(playedThrough(scored(2), [])).toBe(2);
    expect(playedThrough(scored(0), [])).toBeNull();
    expect(
      playedThrough(scored(2), [
        entry("a", "2027test_qm4", "R1"),
        entry("b", "2027test_qm4", "R2"),
      ]),
    ).toBe(2);
  });

  it("falls back to scouted robots when the schedule has no scores", () => {
    expect(
      playedThrough(quals, [
        entry("a", "2027test_qm1", "R1"),
        entry("b", "2027test_qm1", "R2"),
        entry("c", "2027test_qm2", "R1"),
        entry("d", "2027test_qm3", "R1"),
        entry("e", "2027test_QM3", "B2"),
      ]),
    ).toBe(3);
  });

  it("is null with nothing scouted, and counts a station once", () => {
    expect(playedThrough(quals, [])).toBeNull();
    expect(
      playedThrough(quals, [
        entry("a", "2027test_qm1", "R1"),
        entry("b", "2027test_qm1", "R1"),
      ]),
    ).toBeNull();
  });
});

const grid = parseShifts({
  matchCount: 24,
  roster: [
    { uid: "u1", name: "Scout A" },
    { uid: "u2", name: "Scout B" },
  ],
  rotations: [
    {
      uid: "u1",
      shifts: [
        { startMatch: 13, endMatch: 18, station: "R2" },
        { startMatch: 1, endMatch: 6, station: "R1" },
      ],
    },
    { uid: "u2", shifts: [{ startMatch: 7, endMatch: 12, station: "R1" }] },
  ],
});
if (!grid) throw new Error("no grid");

describe("myBlocks", () => {
  it("lists your blocks in match order with how far off they are", () => {
    const blocks = myBlocks(grid, [], "u1", 8);
    expect(blocks?.map((b) => b.block.startMatch)).toEqual([1, 13]);
    expect(blocks?.map((b) => b.away)).toEqual(["done", 4]);
  });

  it("says on duty for the next match, and nothing without a played match", () => {
    expect(myBlocks(grid, [], "u2", 6)?.[0]?.away).toBe(0);
    expect(myBlocks(grid, [], "u2", null)?.[0]?.away).toBeNull();
  });

  it("is null when you are not on the grid or have no uid", () => {
    expect(myBlocks(grid, [], "nobody", 1)).toBeNull();
    expect(myBlocks(grid, [], "", 1)).toBeNull();
  });

  it("follows accepted trades and names the other scout", () => {
    const trades = parseTradeDocs([
      {
        id: "t",
        eventKey: "2027test",
        requesterUid: "u1",
        requesterDisplayName: "Scout A",
        targetUid: "u2",
        targetDisplayName: "Scout B",
        requesterBlock: { startMatch: 13, endMatch: 18 },
        status: "accepted",
        createdAt: "2027-03-04T01:00:00.000Z",
      },
    ]);
    const traded = applyTrades(grid, acceptedTrades(trades));
    const mine = myBlocks(traded, trades, "u2", null);
    expect(mine?.map((b) => b.block.startMatch)).toEqual([7, 13]);
    expect(mine?.[1]?.block.station).toBe("R2");
    expect(mine?.[1]?.tradedWith).toBe("Scout A");
    expect(mine?.[0]?.tradedWith).toBeNull();
    expect(
      myBlocks(traded, trades, "u1", null)?.map((b) => b.block.startMatch),
    ).toEqual([1]);
  });
});

describe("labels", () => {
  it("words the range and the distance", () => {
    expect(rangeText({ startMatch: 7, endMatch: 12 })).toBe("Q7 to Q12");
    expect(rangeText({ startMatch: 7, endMatch: 7 })).toBe("Q7");
    expect(awayText(null)).toBe("");
    expect(awayText("done")).toBe("Done");
    expect(awayText(0)).toBe("On duty now");
    expect(awayText(1)).toBe("1 match away");
    expect(awayText(5)).toBe("5 matches away");
  });
});
