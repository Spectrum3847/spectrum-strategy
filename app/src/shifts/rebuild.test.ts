import { describe, expect, it } from "vitest";
import type { ScoutShifts, ShiftBlock } from "../scout/credit";
import {
  nextBlockStart,
  rebuildFrom,
  rebuildProblems,
  rebuildRounds,
  rebuildStart,
  rebuildWithScouts,
} from "./rebuild";
import { addScouts, blank, markUnavailable } from "./schedule";

const author = { uid: "lead", displayName: "Lead" };

const roster = (n: number, from = 0) =>
  Array.from({ length: n }, (_, i) => ({
    uid: `u${from + i}`,
    name: `Scout ${from + i}`,
  }));

const emptyGrid = (n: number, matchCount: number) =>
  blank({ roster: roster(n), matchCount, author });

const built = (n: number, matchCount: number) =>
  rebuildFrom(emptyGrid(n, matchCount), 1);

const withBlocks = (
  n: number,
  matchCount: number,
  blocks: Record<number, ShiftBlock[]>,
): ScoutShifts => {
  const grid = emptyGrid(n, matchCount);
  return {
    ...grid,
    rotations: grid.rotations.map((r, col) => ({
      ...r,
      blocks: blocks[col] ?? [],
    })),
  };
};

const block = (startMatch: number, endMatch: number, station: string) => ({
  startMatch,
  endMatch,
  station,
});

const red = (...cells: Array<[number, number]>) => {
  const out = new Map<number, Set<number>>();
  for (const [col, match] of cells) {
    out.set(col, (out.get(col) ?? new Set()).add(match));
  }
  return out;
};

const roundsOf = (shifts: ScoutShifts, startMatch: number) =>
  shifts.rotations.filter((r) =>
    r.blocks.some((b) => b.startMatch === startMatch),
  ).length;

describe("nextBlockStart", () => {
  it("is the first match of the block after the last one played", () => {
    expect(nextBlockStart(null)).toBe(1);
    expect(nextBlockStart(0)).toBe(1);
    expect(nextBlockStart(6)).toBe(7);
    expect(nextBlockStart(7)).toBe(13);
    expect(nextBlockStart(14)).toBe(19);
  });
});

describe("rebuildStart and rounds", () => {
  it("starts at the next block start after fromMatch", () => {
    const grid = built(12, 36);
    expect(rebuildStart(grid, 1)).toBe(1);
    expect(rebuildStart(grid, 13)).toBe(13);
    expect(rebuildStart(grid, 14)).toBe(19);
  });

  it("keeps a shift that began before fromMatch whole", () => {
    const grid = withBlocks(1, 30, { 0: [block(1, 12, "R1")] });
    expect(rebuildStart(grid, 7)).toBe(13);
  });

  it("joins a short last round to the one before it", () => {
    expect(rebuildRounds(13, 26)).toEqual([
      { startMatch: 13, endMatch: 18 },
      { startMatch: 19, endMatch: 26 },
    ]);
    expect(rebuildRounds(19, 20)).toEqual([{ startMatch: 19, endMatch: 20 }]);
    expect(rebuildRounds(25, 24)).toEqual([]);
  });
});

describe("rebuildFrom", () => {
  it("keeps every started shift exactly and drops the rest", () => {
    const grid = built(14, 60);
    const next = rebuildFrom(grid, 25);
    grid.rotations.forEach((r, col) => {
      const kept = r.blocks.filter((b) => b.startMatch < 25);
      expect(next.rotations[col]?.blocks.slice(0, kept.length)).toEqual(kept);
      expect(
        next.rotations[col]?.blocks.every(
          (b, i) => i < kept.length || b.startMatch >= 25,
        ),
      ).toBe(true);
    });
  });

  it("staffs all six stations every round with nobody twice", () => {
    const next = rebuildFrom(built(14, 60), 25);
    for (const round of rebuildRounds(25, 60)) {
      const stationsUsed = next.rotations.flatMap((r) =>
        r.blocks
          .filter((b) => b.startMatch === round.startMatch)
          .map((b) => b.station),
      );
      expect(stationsUsed.sort()).toEqual(["B1", "B2", "B3", "R1", "R2", "R3"]);
    }
    expect(rebuildProblems(next, 25)).toEqual([]);
  });

  it("never assigns a scout to a round they are unavailable for", () => {
    const grid = built(14, 60);
    const unavailable = red([0, 31], [3, 25], [3, 40]);
    const next = rebuildFrom(grid, 25, unavailable);
    const on = (col: number) =>
      next.rotations[col]?.blocks.filter((b) => b.startMatch >= 25) ?? [];
    expect(on(0).some((b) => b.startMatch <= 31 && b.endMatch >= 31)).toBe(
      false,
    );
    expect(
      on(3).some(
        (b) =>
          (b.startMatch <= 25 && b.endMatch >= 25) ||
          (b.startMatch <= 40 && b.endMatch >= 40),
      ),
    ).toBe(false);
  });

  it("reads unavailable from red cells by default", () => {
    const grid = markUnavailable(built(14, 60), 2, 25, 36, true) as ScoutShifts;
    const next = rebuildFrom(grid, 25);
    expect(
      next.rotations[2]?.blocks.some(
        (b) => b.startMatch >= 25 && b.startMatch <= 36,
      ),
    ).toBe(false);
  });

  it("counts kept shifts: the scout with fewer shifts is picked first", () => {
    const blocks: Record<number, ShiftBlock[]> = {
      0: [block(1, 6, "R1"), block(13, 18, "R2")],
    };
    for (let col = 1; col <= 5; col++) blocks[col] = [block(1, 6, "R1")];
    for (let col = 6; col <= 11; col++) blocks[col] = [block(7, 12, "R1")];
    const next = rebuildFrom(withBlocks(13, 24, blocks), 19);
    expect(roundsOf(next, 19)).toBe(6);
    expect(next.rotations[12]?.blocks).toEqual([
      expect.objectContaining({ startMatch: 19 }),
    ]);
    expect(next.rotations[0]?.blocks).toHaveLength(2);
  });

  it("prefers the longer rest when shift counts are equal", () => {
    const blocks: Record<number, ShiftBlock[]> = {};
    for (let col = 0; col <= 5; col++) blocks[col] = [block(1, 6, "R1")];
    for (let col = 6; col <= 11; col++) blocks[col] = [block(7, 12, "R1")];
    const next = rebuildFrom(withBlocks(12, 18, blocks), 13);
    for (let col = 0; col <= 5; col++) {
      expect(next.rotations[col]?.blocks).toHaveLength(2);
    }
    for (let col = 6; col <= 11; col++) {
      expect(next.rotations[col]?.blocks).toHaveLength(1);
    }
  });

  it("gives each scout a station other than the ones already done", () => {
    const blocks: Record<number, ShiftBlock[]> = {};
    const names = ["R1", "R2", "R3", "B1", "B2", "B3"];
    names.forEach((s, col) => {
      blocks[col] = [block(1, 6, s)];
    });
    const next = rebuildFrom(withBlocks(6, 12, blocks), 7);
    names.forEach((s, col) => {
      const second = next.rotations[col]?.blocks[1];
      expect(second?.station).not.toBe(s);
      expect(second?.startMatch).toBe(7);
    });
  });

  it("avoids back-to-back shifts when enough scouts are rested", () => {
    const next = rebuildFrom(built(12, 60), 13);
    for (const r of next.rotations) {
      const sorted = [...r.blocks].sort((a, b) => a.startMatch - b.startMatch);
      sorted.slice(1).forEach((b, i) => {
        expect(b.startMatch - (sorted[i]?.endMatch ?? 0)).toBeGreaterThan(1);
      });
    }
  });

  it("extends the last round through the tail", () => {
    const next = rebuildFrom(emptyGrid(12, 20), 7);
    const last = next.rotations.flatMap((r) => r.blocks);
    expect(last.some((b) => b.startMatch === 13 && b.endMatch === 20)).toBe(
      true,
    );
    expect(last.some((b) => b.startMatch === 19)).toBe(false);
  });

  it("staffs a final short round on its own", () => {
    const next = rebuildFrom(built(12, 20), 19);
    expect(roundsOf(next, 19)).toBe(0);
    const grid = withBlocks(12, 20, {});
    expect(roundsOf(rebuildFrom(grid, 19), 19)).toBe(6);
  });

  it("changes nothing when every match has started", () => {
    const grid = built(12, 24);
    expect(rebuildFrom(grid, 25).rotations).toEqual(grid.rotations);
  });

  it("keeps colors, notes and the roster", () => {
    const grid = markUnavailable(built(12, 24), 1, 20, 21, true) as ScoutShifts;
    const next = rebuildFrom(grid, 13);
    expect(next.colors).toEqual(grid.colors);
    expect(next.texts).toEqual(grid.texts);
    expect(next.roster).toEqual(grid.roster);
    expect(next.matchCount).toBe(24);
  });

  it("leaves a stationless kept shift alone and counts it as a shift", () => {
    const grid = withBlocks(7, 12, {
      0: [{ startMatch: 1, endMatch: 6, station: null }],
    });
    const next = rebuildFrom(grid, 7);
    expect(next.rotations[0]?.blocks[0]).toEqual({
      startMatch: 1,
      endMatch: 6,
      station: null,
    });
  });
});

describe("the verified case: kept shifts, blocked scouts, new scouts", () => {
  it("keeps 14 scouts' started shifts, honors 2 blocked scouts, adds 2", () => {
    const base = built(14, 120);
    const from = 55;
    const keptBefore = base.rotations.map((r) =>
      r.blocks.filter((b) => b.startMatch < from),
    );
    let grid = markUnavailable(base, 3, 61, 78, true) as ScoutShifts;
    grid = markUnavailable(grid, 7, 91, 102, true) as ScoutShifts;
    const result = rebuildWithScouts(grid, from, roster(2, 14));
    expect(result).not.toBeNull();
    const { next, summary } = result as NonNullable<typeof result>;

    expect(next.roster).toHaveLength(16);
    keptBefore.forEach((kept, col) => {
      expect(next.rotations[col]?.blocks.slice(0, kept.length)).toEqual(kept);
    });
    const blocked = (col: number, a: number, b: number) =>
      next.rotations[col]?.blocks.some(
        (x) => x.startMatch <= b && x.endMatch >= a,
      );
    expect(blocked(3, 61, 78)).toBe(false);
    expect(blocked(7, 91, 102)).toBe(false);
    expect(rebuildProblems(next, summary.from)).toEqual([]);
    expect(summary.warnings).toEqual([]);

    expect(next.rotations[14]?.blocks.length).toBeGreaterThan(0);
    expect(next.rotations[15]?.blocks.length).toBeGreaterThan(0);
    expect(summary.from).toBe(55);
    expect(summary.keptShifts).toBe(54);
    expect(summary.changed).toContain("Scout 14");

    const totals = next.rotations.map((r) => r.blocks.length);
    expect(Math.max(...totals) - Math.min(...totals)).toBeLessThanOrEqual(2);
  });
});

describe("rebuildProblems", () => {
  it("flags an empty station, a blocked scout and a missing break", () => {
    const grid = withBlocks(3, 12, {
      0: [block(1, 6, "R1"), block(7, 12, "R2")],
      1: [block(7, 12, "R1")],
    });
    const problems = rebuildProblems(grid, 7, red([0, 8]));
    expect(problems).toContain("Q7 to Q12: 4 of 6 stations have no scout.");
    expect(problems).toContain("Q7 to Q12: Scout 0 is marked unavailable.");
    expect(problems).toContain("Q7 to Q12: Scout 0 has no break.");
  });

  it("flags two scouts on one station", () => {
    const grid = withBlocks(2, 6, {
      0: [block(1, 6, "R1")],
      1: [block(1, 6, "R1")],
    });
    expect(rebuildProblems(grid, 1)).toContain(
      "Q1 to Q6: two scouts share a station.",
    );
  });
});

describe("rebuildWithScouts", () => {
  it("summarizes what changed", () => {
    const base = built(12, 36);
    const result = rebuildWithScouts(base, 13, []);
    const { summary } = result as NonNullable<typeof result>;
    expect(summary.from).toBe(13);
    expect(summary.keptShifts).toBe(12);
    expect(summary.newShifts).toBe(24);
    expect(summary.warnings).toEqual([]);
  });

  it("reports a roster that would pass the cap", () => {
    const base = built(60, 12);
    expect(rebuildWithScouts(base, 1, roster(5, 100))).toBeNull();
  });
});

describe("markUnavailable and addScouts", () => {
  it("paints red over a range and clears only red", () => {
    let grid = emptyGrid(2, 12);
    grid = { ...grid, colors: new Map([["0:3", "grey"]]) };
    const marked = markUnavailable(grid, 0, 2, 4, true) as ScoutShifts;
    expect([...marked.colors.entries()].sort()).toEqual([
      ["0:2", "red"],
      ["0:3", "red"],
      ["0:4", "red"],
    ]);
    const other = {
      ...marked,
      colors: new Map(marked.colors).set("0:9", "grey"),
    };
    const cleared = markUnavailable(other, 0, 1, 12, false) as ScoutShifts;
    expect([...cleared.colors.entries()]).toEqual([["0:9", "grey"]]);
  });

  it("appends scouts as new columns and skips names already there", () => {
    const grid = emptyGrid(2, 6);
    const next = addScouts(grid, [
      { uid: "x", name: "scout 1" },
      { uid: "n", name: "New" },
    ]) as ScoutShifts;
    expect(next.roster.map((r) => r.name)).toEqual([
      "Scout 0",
      "Scout 1",
      "New",
    ]);
    expect(next.rotations.map((r) => r.uid)).toEqual(["u0", "u1", "n"]);
  });
});
