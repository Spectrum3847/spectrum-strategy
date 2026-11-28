import { describe, expect, it } from "vitest";
import {
  applyTrades,
  creditFor,
  matchNumberOf,
  parseShifts,
  parseTrades,
  rosterNames,
  type ScoutShifts,
  startStandIn,
} from "./credit";

const names = [..."ABCDEFGHIJKL"].map((c) => `Scout ${c}`);
const stationList = ["R1", "R2", "R3", "B1", "B2", "B3"];

const block = (startMatch: number, endMatch: number, pos: number, had = 0) => ({
  startMatch,
  endMatch,
  station: stationList[(pos + had) % 6],
});

const doc = {
  matchCount: 18,
  roster: names.map((name, i) => ({ uid: `u${i}`, name })),
  rotations: names.map((name, i) => ({
    uid: `u${i}`,
    name,
    shifts:
      i < 6 ? [block(1, 6, i), block(13, 18, i, 1)] : [block(7, 12, i - 6)],
  })),
  cellOverrides: [] as unknown[],
};

const shifts = parseShifts(doc);
if (!shifts) throw new Error("fixture does not parse");

const input = (over: Partial<Parameters<typeof creditFor>[0]> = {}) => ({
  shifts,
  station: "R1",
  match: 3,
  eventKey: "2027test",
  standIn: null,
  ...over,
});

const grid = (over: Record<string, unknown>) =>
  parseShifts({ ...doc, ...over });
const who = (
  station: string,
  match: number,
  from: ScoutShifts | null = shifts,
) => creditFor(input({ shifts: from, station, match }))?.name;

describe("parseShifts", () => {
  it("returns null without a roster or for junk", () => {
    expect(parseShifts(null)).toBeNull();
    expect(parseShifts({ roster: [] })).toBeNull();
    expect(parseShifts("x")).toBeNull();
  });

  it("keeps stations and painted colors and tolerates bad rows", () => {
    const parsed = parseShifts({
      roster: [{ uid: "a", name: " Ada " }, 5],
      rotations: [
        {
          uid: "a",
          shifts: [
            { startMatch: 1, endMatch: 2, station: "Red 2" },
            { startMatch: 3, endMatch: 4 },
            { startMatch: 5, endMatch: 6, station: "pit" },
            "x",
          ],
        },
      ],
      cellOverrides: [{ col: 0, match: 4, color: "green", text: "" }, null],
    });
    expect(parsed?.roster).toEqual([{ uid: "a", name: "Ada" }]);
    expect(parsed?.rotations[0]?.blocks.map((b) => b.station)).toEqual([
      "R2",
      null,
      null,
    ]);
    expect(parsed?.colors.get("0:4")).toBe("green");
  });
});

describe("creditFor", () => {
  it("credits the scout whose block has the station", () => {
    expect(who("R1", 3)).toBe("Scout A");
    expect(who("R3", 3)).toBe("Scout C");
    expect(who("B3", 3)).toBe("Scout F");
    expect(who("R1", 8)).toBe("Scout G");
    expect(who("B3", 8)).toBe("Scout L");
  });

  it("follows the station as it rotates, not the column", () => {
    expect(who("R1", 14)).toBe("Scout F");
    expect(who("R2", 14)).toBe("Scout A");
    expect(who("B3", 14)).toBe("Scout E");
  });

  it("carries the account uid", () => {
    expect(creditFor(input({ station: "R2" }))).toEqual({
      name: "Scout B",
      uid: "u1",
      standIn: false,
    });
  });

  it("is null when nobody holds the station or inputs are missing", () => {
    expect(creditFor(input({ match: 100 }))).toBeNull();
    expect(creditFor(input({ match: 20 }))).toBeNull();
    expect(creditFor(input({ shifts: null }))).toBeNull();
    expect(creditFor(input({ station: null }))).toBeNull();
    expect(creditFor(input({ match: null }))).toBeNull();
    expect(creditFor(input({ station: "pit" }))).toBeNull();
  });

  it("does not shift anyone when fewer than six are on duty", () => {
    const three = grid({
      rotations: [0, 1, 2].map((i) => ({
        uid: `u${i}`,
        shifts: [block(1, 6, i + 3)],
      })),
    });
    expect(who("B1", 3, three)).toBe("Scout A");
    expect(who("B3", 3, three)).toBe("Scout C");
    expect(who("R1", 3, three)).toBeUndefined();
  });

  it("does not use column order when more than six are on duty", () => {
    const seven = grid({
      rotations: [...Array(7).keys()].map((i) => ({
        uid: `u${i}`,
        shifts: [
          i === 6 ? { startMatch: 1, endMatch: 6 } : block(1, 6, (i + 4) % 6),
        ],
      })),
    });
    expect(who("R1", 3, seven)).toBe("Scout C");
    expect(who("R2", 3, seven)).toBe("Scout D");
    expect(who("B3", 3, seven)).toBe("Scout B");
  });

  it("credits nobody on a grid saved without stations", () => {
    const old = grid({
      rotations: names.map((_, i) => ({
        uid: `u${i}`,
        shifts: [{ startMatch: 1, endMatch: 18 }],
      })),
    });
    for (const station of stationList) {
      expect(who(station, 3, old)).toBeUndefined();
    }
  });

  it("credits nobody when two scouts claim one station", () => {
    const clash = grid({
      rotations: [0, 1].map((i) => ({
        uid: `u${i}`,
        shifts: [block(1, 6, 0)],
      })),
    });
    expect(who("R1", 3, clash)).toBeUndefined();
  });

  it("treats a cell painted off as no credit, not a hand-off", () => {
    const off = grid({
      cellOverrides: [{ col: 0, match: 3, color: "red", text: "" }],
    });
    expect(who("R1", 3, off)).toBeUndefined();
    expect(who("R1", 4, off)).toBe("Scout A");
    expect(who("R2", 3, off)).toBe("Scout B");
  });

  it("keeps the credit for a cell painted green on the block", () => {
    const green = grid({
      cellOverrides: [{ col: 0, match: 3, color: "green", text: "" }],
    });
    expect(who("R1", 3, green)).toBe("Scout A");
  });

  it("gives a hand-painted green cell with no block no station", () => {
    const painted = grid({
      cellOverrides: [{ col: 7, match: 3, color: "green", text: "" }],
    });
    for (const station of stationList) {
      expect(who(station, 3, painted)).toBe(who(station, 3));
    }
    expect(who("R1", 20, painted)).toBeUndefined();
  });

  it("ignores a note with no color", () => {
    const noted = grid({
      cellOverrides: [{ col: 0, match: 3, text: "lunch" }],
    });
    expect(who("R1", 3, noted)).toBe("Scout A");
  });
});

describe("shift trades", () => {
  const trade = (over: Record<string, unknown> = {}) => ({
    status: "accepted",
    requesterUid: "u0",
    targetUid: "u6",
    requesterBlock: { startMatch: 1, endMatch: 6 },
    createdAt: "2027-03-01T10:00:00.000Z",
    ...over,
  });
  const traded = (docs: unknown[]) => applyTrades(shifts, parseTrades(docs));

  it("keeps only accepted trades, newest first", () => {
    const parsed = parseTrades([
      trade({ status: "pending" }),
      trade({ status: "declined" }),
      trade({ createdAt: "2027-03-01T10:00:00.000Z", targetUid: "old" }),
      trade({ createdAt: "2027-03-02T10:00:00.000Z", targetUid: "new" }),
      trade({ requesterBlock: { startMatch: 0, endMatch: 6 } }),
      "x",
    ]);
    expect(parsed.map((t) => t.targetUid)).toEqual(["new", "old"]);
  });

  it("puts the taker on the block at the giver's station", () => {
    const after = traded([trade()]);
    expect(who("R1", 3, after)).toBe("Scout G");
    expect(who("R1", 3, after)).not.toBe("Scout A");
    expect(who("R2", 3, after)).toBe("Scout B");
    expect(who("R1", 14, after)).toBe("Scout F");
    expect(who("R1", 8, after)).toBe("Scout G");
  });

  it("swaps both ways when the trade offers a block back", () => {
    const after = traded([
      trade({ targetBlock: { startMatch: 7, endMatch: 12 } }),
    ]);
    expect(who("R1", 3, after)).toBe("Scout G");
    expect(who("R1", 8, after)).toBe("Scout A");
  });

  it("ignores pending trades", () => {
    expect(who("R1", 3, traded([trade({ status: "pending" })]))).toBe(
      "Scout A",
    );
  });

  it("changes nothing when a side left the roster or has no uid", () => {
    expect(who("R1", 3, traded([trade({ targetUid: "gone" })]))).toBe(
      "Scout A",
    );
    expect(who("R1", 3, traded([trade({ requesterUid: "" })]))).toBe("Scout A");
  });

  it("ignores a trade for a block the giver no longer has", () => {
    const after = traded([
      trade({ requesterBlock: { startMatch: 2, endMatch: 7 } }),
    ]);
    expect(after.rotations).toEqual(shifts.rotations);
  });

  it("does not credit a taker painted off for the match", () => {
    const off = grid({
      cellOverrides: [{ col: 6, match: 3, color: "white", text: "" }],
    });
    if (!off) throw new Error("fixture does not parse");
    expect(who("R1", 3, applyTrades(off, parseTrades([trade()])))).toBe(
      undefined,
    );
  });

  it("leaves the grid alone with no trades", () => {
    expect(applyTrades(shifts, [])).toBe(shifts);
  });
});

describe("stand-in", () => {
  const picked = { name: "Zed", uid: "" };
  const start = (match: number, station = "red 1", from = shifts) =>
    startStandIn({
      shifts: from,
      station,
      match,
      eventKey: "2027test",
      who: picked,
    });

  it("lasts to the end of the block at the station", () => {
    const standIn = start(4);
    expect(standIn).toMatchObject({
      station: "R1",
      name: "Zed",
      fromMatch: 4,
      untilMatch: 6,
    });
    const at = (match: number) => creditFor(input({ match, standIn }))?.name;
    expect(at(4)).toBe("Zed");
    expect(at(6)).toBe("Zed");
    expect(creditFor(input({ match: 6, standIn }))?.standIn).toBe(true);
    expect(at(7)).toBe("Scout G");
  });

  it("still ends at the block when the scheduled scout is painted off", () => {
    const off = grid({
      cellOverrides: [{ col: 0, match: 3, color: "red", text: "" }],
    });
    if (!off) throw new Error("fixture does not parse");
    expect(start(3, "R1", off).untilMatch).toBe(6);
  });

  it("does not credit earlier matches, other stations or events", () => {
    const standIn = start(4);
    expect(creditFor(input({ match: 3, standIn }))?.name).toBe("Scout A");
    expect(creditFor(input({ station: "R2", standIn }))?.name).toBe("Scout B");
    expect(
      creditFor(input({ match: 5, eventKey: "2027other", standIn }))?.name,
    ).toBe("Scout A");
  });

  it("ends after 6 matches inside a long block", () => {
    const long = grid({
      roster: names.slice(0, 6).map((name, i) => ({ uid: `u${i}`, name })),
      rotations: names
        .slice(0, 6)
        .map((name, i) => ({ uid: `u${i}`, name, shifts: [block(1, 30, i)] })),
    });
    if (!long) throw new Error("fixture does not parse");
    expect(start(10, "R1", long).untilMatch).toBe(15);
  });

  it("takes 6 matches when no block holds the station", () => {
    const standIn = start(20, "R3");
    expect(standIn.untilMatch).toBe(25);
    expect(creditFor(input({ station: "R3", match: 20, standIn }))?.name).toBe(
      "Zed",
    );
    expect(creditFor(input({ station: "R3", match: 26, standIn }))).toBeNull();
  });

  it("trims and bounds the name", () => {
    const standIn = startStandIn({
      shifts,
      station: "R1",
      match: 1,
      eventKey: "e",
      who: { name: `  ${"x".repeat(200)}`, uid: "" },
    });
    expect(standIn.name).toHaveLength(128);
  });
});

describe("helpers", () => {
  it("lists roster names once", () => {
    const parsed = parseShifts({
      roster: [
        { uid: "a", name: "Ada" },
        { uid: "", name: "ada" },
        { uid: "", name: "" },
        { uid: "b", name: "Ben" },
      ],
    });
    expect(parsed && rosterNames(parsed).map((r) => r.name)).toEqual([
      "Ada",
      "Ben",
    ]);
  });

  it("reads a match number", () => {
    expect(matchNumberOf(" 12 ")).toBe(12);
    expect(matchNumberOf("")).toBeNull();
    expect(matchNumberOf("0")).toBeNull();
    expect(matchNumberOf("abc")).toBeNull();
  });
});
