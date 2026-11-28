import { describe, expect, it } from "vitest";
import { parseShifts, type ScoutShifts } from "../scout/credit";
import {
  blank,
  cellsBetween,
  colorAt,
  generate,
  hasRotation,
  labelAt,
  maxOverrides,
  paint,
  stationAt,
  toDoc,
} from "./schedule";

const names = ["Scout A", "Scout B", "Scout C"];
const author = { uid: "lead", displayName: "Lead Ann" };
const now = new Date("2027-03-04T05:06:07.123Z");

const fresh = (matchCount = 12): ScoutShifts =>
  blank({
    roster: names.map((name, i) => ({ uid: i === 2 ? "" : `u${i}`, name })),
    matchCount,
    author,
  });

const must = <T>(v: T | null): T => {
  if (v === null) throw new Error("unexpected null");
  return v;
};

describe("blank", () => {
  it("stores the roster with no shifts and every cell white", () => {
    const s = fresh();
    expect(hasRotation(s)).toBe(false);
    expect(s.rotations).toHaveLength(3);
    expect(colorAt(s, 0, 3)).toBe("white");
    expect(labelAt(s, 0, 3)).toBe("");
  });

  it("refuses a match count past the rules' cap and floors a negative one", () => {
    expect(() => fresh(1000)).toThrow();
    expect(fresh(-4).matchCount).toBe(0);
  });
});

describe("generate", () => {
  it("fills the rotation and shows stations on green cells", () => {
    const s = generate(fresh());
    expect(hasRotation(s)).toBe(true);
    expect(colorAt(s, 0, 2)).toBe("green");
    expect(labelAt(s, 0, 2)).toBe("R1");
    expect(stationAt(s, 1, 2)).toBe("R2");
    expect(colorAt(s, 0, 13)).toBe("white");
  });

  it("keeps notes and routes around a red cell", () => {
    const painted = must(
      paint(fresh(6), [{ col: 0, match: 2 }], { color: "red", text: "pit" }),
    );
    const s = generate(painted);
    expect(s.rotations[0]?.blocks).toEqual([]);
    expect(colorAt(s, 0, 2)).toBe("red");
    expect(labelAt(s, 0, 2)).toBe("pit");
    expect(s.rotations[1]?.blocks[0]?.station).toBe("R1");
  });

  it("ignores grey and white paint, as the Dart generator does", () => {
    const painted = must(
      paint(fresh(6), [{ col: 0, match: 2 }], { color: "grey" }),
    );
    expect(generate(painted).rotations).toEqual(generate(fresh(6)).rotations);
  });
});

describe("paint", () => {
  it("sets a color, keeps the note, and clears back to the default", () => {
    const base = generate(fresh(6));
    const noted = must(paint(base, [{ col: 0, match: 2 }], { text: "lunch" }));
    const red = must(paint(noted, [{ col: 0, match: 2 }], { color: "red" }));
    expect(colorAt(red, 0, 2)).toBe("red");
    expect(labelAt(red, 0, 2)).toBe("lunch");
    const cleared = must(
      paint(red, [{ col: 0, match: 2 }], { color: null, text: "" }),
    );
    expect(colorAt(cleared, 0, 2)).toBe("green");
    expect(cleared.colors.size).toBe(0);
    expect(cleared.texts.size).toBe(0);
  });

  it("shows no station on a cell painted green by hand", () => {
    const s = must(paint(fresh(6), [{ col: 0, match: 2 }], { color: "green" }));
    expect(colorAt(s, 0, 2)).toBe("green");
    expect(labelAt(s, 0, 2)).toBe("");
  });

  it("skips cells outside the grid", () => {
    const s = must(
      paint(
        fresh(6),
        [
          { col: 5, match: 1 },
          { col: 0, match: 7 },
          { col: 0, match: 0 },
          { col: -1, match: 1 },
        ],
        { color: "red" },
      ),
    );
    expect(s.colors.size).toBe(0);
  });

  it("paints the rectangle between two corners", () => {
    const rect = cellsBetween({ col: 2, match: 5 }, { col: 0, match: 3 });
    expect(rect).toHaveLength(9);
    const s = must(paint(fresh(), rect, { color: "grey" }));
    expect(s.colors.size).toBe(9);
    expect(colorAt(s, 1, 4)).toBe("grey");
  });

  it("returns null past the cap on cell edits and leaves the grid alone", () => {
    const big = blank({
      roster: Array.from({ length: 64 }, (_, i) => ({
        uid: "",
        name: `S${i}`,
      })),
      matchCount: 999,
      author,
    });
    const cells = cellsBetween(
      { col: 0, match: 1 },
      { col: 63, match: maxOverrides / 64 + 1 },
    );
    expect(paint(big, cells, { color: "red" })).toBeNull();
    expect(big.colors.size).toBe(0);
  });
});

describe("toDoc", () => {
  const allowed = [
    "id",
    "eventKey",
    "matchCount",
    "roster",
    "rotations",
    "cellOverrides",
    "authorUid",
    "authorDisplayName",
    "updatedAt",
    "updatedAtTs",
  ];

  it("writes exactly the allowed keys", () => {
    const doc = toDoc(generate(fresh()), "2027test", now);
    expect(Object.keys(doc).sort()).toEqual([...allowed].sort());
    expect(doc.id).toBe("2027test");
    expect(doc.eventKey).toBe("2027test");
    expect(doc.matchCount).toBe(12);
    expect(doc.authorUid).toBe("lead");
    expect(doc.updatedAt).toBe("2027-03-04T05:06:07.123Z");
  });

  it("writes roster, rotations with stations and cell edits like toJson", () => {
    const painted = must(
      paint(generate(fresh(6)), [{ col: 1, match: 3 }], {
        color: "red",
        text: "pit",
      }),
    );
    const noteOnly = must(
      paint(painted, [{ col: 0, match: 1 }], { text: "x" }),
    );
    const doc = toDoc(noteOnly, "2027test", now);
    expect(doc.roster).toEqual([
      { uid: "u0", name: "Scout A" },
      { uid: "u1", name: "Scout B" },
      { uid: "", name: "Scout C" },
    ]);
    expect(doc.rotations).toEqual([
      {
        uid: "u0",
        name: "Scout A",
        shifts: [{ startMatch: 1, endMatch: 6, station: "R1" }],
      },
      {
        uid: "u1",
        name: "Scout B",
        shifts: [{ startMatch: 1, endMatch: 6, station: "R2" }],
      },
      {
        uid: "",
        name: "Scout C",
        shifts: [{ startMatch: 1, endMatch: 6, station: "R3" }],
      },
    ]);
    expect(doc.cellOverrides).toEqual([
      { col: 0, match: 1, text: "x" },
      { col: 1, match: 3, text: "pit", color: "red" },
    ]);
  });

  it("round-trips through the parser the Scout tab already uses", () => {
    const painted = must(
      paint(generate(fresh(18)), [{ col: 2, match: 4 }], {
        color: "grey",
        text: "drive team",
      }),
    );
    const parsed = parseShifts(toDoc(painted, "2027test", now));
    expect(parsed?.roster).toEqual(painted.roster);
    expect(parsed?.rotations).toEqual(painted.rotations);
    expect(parsed?.colors).toEqual(painted.colors);
    expect(parsed?.texts).toEqual(painted.texts);
    expect(parsed?.matchCount).toBe(18);
    expect(parsed?.authorUid).toBe("lead");
  });

  it("omits a block's station when it has none", () => {
    const s = fresh();
    s.rotations[0] = {
      uid: "u0",
      blocks: [{ startMatch: 1, endMatch: 2, station: null }],
    };
    const doc = toDoc(s, "2027test", now);
    expect(
      (doc.rotations as Array<{ shifts: unknown[] }>)[0]?.shifts[0],
    ).toEqual({ startMatch: 1, endMatch: 2 });
  });
});
