import { describe, expect, it } from "vitest";
import { emptyRow, type TeamRow } from "./rows";
import {
  defaultPlaces,
  defaultSort,
  orderNotice,
  searchRows,
  sortRows,
} from "./sort";

const row = (team: number, over: Partial<TeamRow> = {}): TeamRow => ({
  ...emptyRow(team),
  listed: true,
  ...over,
});

const order = (rows: TeamRow[]) => rows.map((r) => r.team);

describe("default order", () => {
  it("is EPA high to low, then TBA rank, then number", () => {
    const rows = [
      row(5, { rank: 1 }),
      row(4, { epa: 10, rank: 9 }),
      row(3, { epa: 30 }),
      row(2, { rank: 2 }),
      row(1),
    ];
    expect(order(sortRows(rows, defaultSort))).toEqual([3, 4, 5, 2, 1]);
  });

  it("is the TBA rank order when nobody has EPA", () => {
    const rows = [
      row(1, { rank: 3 }),
      row(2, { rank: 1 }),
      row(3, { rank: 2 }),
    ];
    expect(order(sortRows(rows, defaultSort))).toEqual([2, 3, 1]);
  });

  it("gives each team its place whatever the sort", () => {
    const rows = [row(1, { epa: 5 }), row(2, { epa: 9 })];
    expect(defaultPlaces(rows).get(2)).toBe(1);
    expect(defaultPlaces(rows).get(1)).toBe(2);
  });
});

describe("sortRows", () => {
  const rows = [
    row(1, { total: 10, sd: 4, epa: 1 }),
    row(2, { total: 30, sd: 1, epa: 2 }),
    row(3, { total: 20, epa: 3 }),
    row(4, { epa: 4 }),
  ];

  it("puts the best first for a stat and the lowest for a spread", () => {
    expect(order(sortRows(rows, { key: "total", reversed: false }))).toEqual([
      2, 3, 1, 4,
    ]);
    expect(order(sortRows(rows, { key: "sd", reversed: false }))).toEqual([
      2, 1, 4, 3,
    ]);
  });

  it("sorts by floor and by the share of matches without a breakdown", () => {
    const risk = [
      row(1, { floor: 5, reliability: { ok: 6, of: 10 }, epa: 1 }),
      row(2, { floor: 12, reliability: { ok: 10, of: 10 }, epa: 2 }),
      row(3, { floor: 9, reliability: { ok: 4, of: 5 }, epa: 3 }),
      row(4, { epa: 4 }),
    ];
    expect(order(sortRows(risk, { key: "floor", reversed: false }))).toEqual([
      2, 3, 1, 4,
    ]);
    expect(order(sortRows(risk, { key: "reliable", reversed: false }))).toEqual(
      [2, 3, 1, 4],
    );
  });

  it("keeps EPA as the default sort", () => {
    expect(defaultSort.key).toBe("epa");
  });

  it("reverses the present values and keeps missing ones last", () => {
    expect(order(sortRows(rows, { key: "total", reversed: true }))).toEqual([
      1, 3, 2, 4,
    ]);
  });

  it("sorts by number and by best climb", () => {
    expect(order(sortRows(rows, { key: "number", reversed: false }))).toEqual([
      1, 2, 3, 4,
    ]);
    const climbs = [row(1, { climb: 1 }), row(2, { climb: 3 }), row(3)];
    expect(order(sortRows(climbs, { key: "climb", reversed: false }))).toEqual([
      2, 1, 3,
    ]);
  });

  it("breaks a tie by the default order", () => {
    const tied = [row(1, { total: 5, epa: 1 }), row(2, { total: 5, epa: 9 })];
    expect(order(sortRows(tied, { key: "total", reversed: false }))).toEqual([
      2, 1,
    ]);
  });

  it("does not change the rows it was given", () => {
    const before = order(rows);
    sortRows(rows, { key: "total", reversed: false });
    expect(order(rows)).toEqual(before);
  });
});

describe("orderNotice", () => {
  it("says nothing when EPA covers every team", () => {
    expect(orderNotice([row(1, { epa: 5 })], "ready")).toBeNull();
  });

  it("says teams without EPA follow in rank order", () => {
    expect(orderNotice([row(1, { epa: 5 }), row(2)], "ready")).toMatch(
      /1 team has no EPA/,
    );
  });

  it("names the fallback when Statbotics has nothing", () => {
    const rows = [row(1, { rank: 1 })];
    expect(orderNotice(rows, "ready")).toMatch(/no EPA .* TBA rank/);
    expect(orderNotice(rows, "failed")).toMatch(/could not be reached/);
    expect(orderNotice(rows, "loading")).toMatch(/Waiting for Statbotics/);
  });

  it("falls back to number when no rank is posted", () => {
    expect(orderNotice([row(1)], "ready")).toMatch(/team number/);
  });

  it("is empty with no teams", () => {
    expect(orderNotice([], "ready")).toBeNull();
  });
});

describe("searchRows", () => {
  const rows = [
    row(254, { nickname: "The Cheesy Poofs" }),
    row(2543, { nickname: "Robo Owls" }),
    row(1678, { nickname: "Citrus Circuits" }),
  ];

  it("matches a number by its start", () => {
    expect(order(searchRows(rows, "254"))).toEqual([254, 2543]);
    expect(order(searchRows(rows, "frc1678"))).toEqual([1678]);
  });

  it("matches a nickname anywhere, ignoring case", () => {
    expect(order(searchRows(rows, "circuit"))).toEqual([1678]);
    expect(order(searchRows(rows, "OWL"))).toEqual([2543]);
  });

  it("returns every team for an empty search", () => {
    expect(searchRows(rows, "  ")).toHaveLength(3);
  });
});
