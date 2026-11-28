import { describe, expect, it } from "vitest";
import pitBundled from "../../../assets/pit_scout_config_default.json";
import type { PitEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import {
  bestFlags,
  buildMetrics,
  compareHref,
  newestPit,
  parseCompare,
  tieGroups,
  tieNote,
} from "./compare";
import { emptyRow, type TeamRow } from "./rows";

const pitConfig = parseConfig(pitBundled);

const row = (team: number, over: Partial<TeamRow> = {}): TeamRow => ({
  ...emptyRow(team),
  listed: true,
  ...over,
});

const pit = (
  team: number,
  updatedAt: string,
  fieldValues: Record<string, unknown>,
): PitEntry => ({
  id: `${team}-${updatedAt}`,
  teamNumber: team,
  eventKey: "",
  fieldValues,
  authorUid: "u1",
  scoutName: "Scout A",
  updatedAt,
  photoKeys: [],
});

describe("parseCompare", () => {
  it("reads numbers once each, at most four", () => {
    expect(parseCompare("1111,2222,1111,3333,4444,5555")).toEqual([
      1111, 2222, 3333, 4444,
    ]);
  });

  it("skips what is not a team number", () => {
    expect(parseCompare("abc,,frc254, 1678")).toEqual([254, 1678]);
    expect(parseCompare(null)).toEqual([]);
  });

  it("makes the address back", () => {
    expect(compareHref([1111, 2222])).toBe("/teams/compare?t=1111,2222");
    expect(compareHref([])).toBe("/teams/compare");
  });
});

describe("bestFlags", () => {
  it("marks the best, high or low", () => {
    expect(bestFlags([1, 5, 3], true)).toEqual([false, true, false]);
    expect(bestFlags([1, 5, 3], false)).toEqual([true, false, false]);
  });

  it("marks nothing for a tie, one value or none", () => {
    expect(bestFlags([4, 4], true)).toEqual([false, false]);
    expect(bestFlags([4, null], true)).toEqual([false, false]);
    expect(bestFlags([null, null], true)).toEqual([false, false]);
  });

  it("marks every team that shares the best", () => {
    expect(bestFlags([5, 5, 1], true)).toEqual([true, true, false]);
  });
});

describe("tieNote", () => {
  const scored = (team: number, total: number, totalSe: number | null) =>
    row(team, { total, totalSe });

  it("says nothing when every team is clear of the others", () => {
    expect(
      tieNote([scored(1111, 100, 3), scored(2222, 60, 3)]),
    ).toBeUndefined();
  });

  it("names the teams that are too close to call", () => {
    expect(
      tieNote([
        scored(1111, 100, 6),
        scored(2222, 104, 6),
        scored(3333, 50, 3),
      ]),
    ).toBe("Too close to call: 1111, 2222.");
  });

  it("groups teams linked through a third, and lists separate groups", () => {
    const rows = [
      scored(1, 100, 6),
      scored(2, 106, 6),
      scored(3, 112, 6),
      scored(4, 50, 2),
      scored(5, 51, 2),
    ];
    expect(tieGroups(rows)).toEqual([
      [1, 2, 3],
      [4, 5],
    ]);
    expect(tieNote(rows)).toBe("Too close to call: 1, 2, 3; 4, 5.");
  });

  it("ignores a team with no score or no error", () => {
    expect(
      tieNote([scored(1111, 100, null), scored(2222, 100, 5), row(3333)]),
    ).toBeUndefined();
  });

  it("sits under the scouted score row, and only there", () => {
    const rows = [scored(1111, 100, 6), scored(2222, 104, 6)];
    const groups = buildMetrics(rows, new Map(), pitConfig);
    const all = groups.flatMap((g) => g.metrics);
    expect(all.find((m) => m.id === "total")?.note).toBe(
      "Too close to call: 1111, 2222.",
    );
    expect(all.filter((m) => m.note !== undefined)).toHaveLength(1);
  });
});

describe("buildMetrics", () => {
  const rows = [
    row(1111, {
      epa: 30,
      rank: 5,
      record: "3-2-0",
      matches: 4,
      total: 20,
      sd: 2,
      form: 3,
      climb: 3,
    }),
    row(2222, { epa: 25, rank: 2, total: 28, sd: 6, form: -2.5 }),
  ];
  const metrics = (rowsIn = rows, entries: PitEntry[] = []) =>
    buildMetrics(rowsIn, newestPit(entries), pitConfig);
  const metric = (id: string, rowsIn = rows, entries: PitEntry[] = []) =>
    metrics(rowsIn, entries)
      .flatMap((g) => g.metrics)
      .find((m) => m.id === id);

  it("puts the standard error under each average and nowhere else", () => {
    const withError = [
      row(1111, { total: 20, totalSe: 2.46, auto: 5, autoSe: 1, teleop: 15 }),
      row(2222, { total: 28, totalSe: null }),
    ];
    expect(metric("total", withError)?.cells.map((c) => c.error)).toEqual([
      "±2.5",
      undefined,
    ]);
    expect(metric("auto", withError)?.cells[0]?.error).toBe("±1");
    expect(metric("teleop", withError)?.cells[0]?.error).toBeUndefined();
    expect(metric("epa", withError)?.cells[0]?.error).toBeUndefined();
  });

  it("adds floor and reliability rows, the best being the highest", () => {
    const risk = [
      row(1111, { floor: 9, reliability: { ok: 9, of: 10 } }),
      row(2222, { floor: 14, reliability: { ok: 5, of: 5 } }),
    ];
    expect(metric("floor", risk)?.cells.map((c) => c.text)).toEqual([
      "9",
      "14",
    ]);
    expect(metric("floor", risk)?.cells.map((c) => c.best)).toEqual([
      false,
      true,
    ]);
    expect(metric("reliability", risk)?.cells.map((c) => c.text)).toEqual([
      "9 of 10",
      "5 of 5",
    ]);
    expect(metric("reliability", risk)?.cells.map((c) => c.best)).toEqual([
      false,
      true,
    ]);
    expect(metric("reliability")?.cells.map((c) => c.text)).toEqual([
      null,
      null,
    ]);
  });

  it("marks the best of each stat, and a low rank and spread as best", () => {
    expect(metric("epa")?.cells.map((c) => c.best)).toEqual([true, false]);
    expect(metric("rank")?.cells.map((c) => c.best)).toEqual([false, true]);
    expect(metric("sd")?.cells.map((c) => c.best)).toEqual([true, false]);
    expect(metric("total")?.cells.map((c) => c.best)).toEqual([false, true]);
  });

  it("formats the cells and leaves missing ones null", () => {
    expect(metric("form")?.cells.map((c) => c.text)).toEqual(["+3", "-2.5"]);
    expect(metric("climb")?.cells.map((c) => c.text)).toEqual(["L3", null]);
    expect(metric("record")?.cells.map((c) => c.text)).toEqual(["3-2-0", null]);
  });

  it("never calls a matches count best", () => {
    expect(metric("matches")?.cells.every((c) => !c.best)).toBe(true);
  });

  it("carries each team's match totals for the trend row", () => {
    const withSeries = [
      row(1111, { series: [{ key: "2027test_qm1", value: 4 }] }),
    ];
    expect(metric("trend", withSeries)?.cells[0]?.series).toHaveLength(1);
  });

  it("reads pit answers from the newest entry and names teams without one", () => {
    const entries = [
      pit(1111, "2027-03-01T10:00:00.000Z", { trenchFit: false }),
      pit(1111, "2027-03-01T12:00:00.000Z", {
        trenchFit: true,
        drivetrainType: "swerve",
      }),
    ];
    expect(
      metric("pit-trenchFit", rows, entries)?.cells.map((c) => c.text),
    ).toEqual(["Yes", null]);
    expect(metric("pit-type", rows, entries)?.cells[0]?.text).toBe(
      "Swerve · trench",
    );
    const group = metrics(rows, entries).find((g) => g.id === "pit");
    expect(group?.note).toBe("No pit entry yet for 2222.");
  });

  it("drops a pit row the config no longer asks", () => {
    const bare = parseConfig({ sections: [] });
    const found = buildMetrics(rows, new Map(), bare)
      .flatMap((g) => g.metrics)
      .map((m) => m.id);
    expect(found).not.toContain("pit-trenchFit");
    expect(found).toContain("pit-type");
  });
});
