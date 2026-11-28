import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry, PitEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import {
  countOf,
  evaluateFilters,
  type FilterId,
  filterDefs,
  filterGroups,
  parseFilters,
  passes,
} from "./filters";

const config = parseConfig(bundled);

function entry(
  team: number,
  match: number,
  fieldValues: Record<string, unknown> = {},
): EventEntry {
  return {
    id: `${team}-${match}`,
    tbaMatchKey: `2027test_qm${match}`,
    teamNumber: team,
    alliance: "Red",
    scoutName: "Scout A",
    updatedAt: "2027-03-01T12:00:00.000Z",
    fieldValues: { autoFuelScored: 0, teleopFuelScored: 10, ...fieldValues },
  };
}

function pit(team: number, fieldValues: Record<string, unknown>): PitEntry {
  return {
    id: `pit-${team}`,
    teamNumber: team,
    eventKey: "2027test",
    fieldValues,
    authorUid: "u1",
    scoutName: "Scout A",
    updatedAt: "2027-03-01T10:00:00.000Z",
    photoKeys: [],
  };
}

const run = (entries: EventEntry[], teams: number[], pits: PitEntry[] = []) =>
  evaluateFilters({
    config,
    teams,
    entries,
    pit: new Map(pits.map((p) => [p.teamNumber, p])),
  });

const teamsOf = (r: ReturnType<typeof run>, id: FilterId) =>
  [...r.passing[id]].sort();

describe("climb filters", () => {
  it("need a successful climb in a scout entry", () => {
    const r = run(
      [
        entry(1111, 1, { eHigh: "Successful", auLow: "Successful" }),
        entry(2222, 1, { eHigh: "Failed", auLow: "Not Attempted" }),
        entry(3333, 1, { eHigh: "Middle" }),
      ],
      [1111, 2222, 3333, 4444],
    );
    expect(teamsOf(r, "l3")).toEqual([1111, 3333]);
    expect(teamsOf(r, "autoclimb")).toEqual([1111]);
  });
});

describe("role filters", () => {
  it("need 2 entries and 30 percent", () => {
    const r = run(
      [
        entry(1111, 1, { tRdefense: true }),
        entry(1111, 2, { tRdefense: false }),
        entry(2222, 1, { tRdefense: true }),
        entry(3333, 1, { tRpasser: "true" }),
        entry(3333, 2, {}),
        entry(3333, 3, {}),
        entry(3333, 4, {}),
      ],
      [1111, 2222, 3333],
    );
    expect(teamsOf(r, "defense")).toEqual([1111]);
    expect(teamsOf(r, "passer")).toEqual([]);
  });

  it("passes at exactly 30 percent", () => {
    const entries = [1, 2, 3].map((m) => entry(1111, m, { tRpasser: m <= 0 }));
    const ten = Array.from({ length: 10 }, (_, i) =>
      entry(2222, i + 1, { tRpasser: i < 3 }),
    );
    const r = run([...entries, ...ten], [1111, 2222]);
    expect(teamsOf(r, "passer")).toEqual([2222]);
  });
});

describe("top scorer", () => {
  it("needs four teams with data, then the top quarter", () => {
    const three = [1111, 2222, 3333].map((t, i) =>
      entry(t, 1, { teleopFuelScored: 10 * (i + 1) }),
    );
    expect(teamsOf(run(three, [1111, 2222, 3333]), "scorer")).toEqual([]);
    const four = [1111, 2222, 3333, 4444].map((t, i) =>
      entry(t, 1, { teleopFuelScored: 10 * (i + 1) }),
    );
    expect(teamsOf(run(four, [1111, 2222, 3333, 4444]), "scorer")).toEqual([
      4444,
    ]);
  });
});

describe("trust filters", () => {
  it("clean record needs a scouted team without cards or deaths", () => {
    const r = run(
      [
        entry(1111, 1),
        entry(2222, 1, { ryCard: "Yellow" }),
        entry(3333, 1, { dieCard: true }),
      ],
      [1111, 2222, 3333, 4444],
    );
    expect(teamsOf(r, "clean")).toEqual([1111]);
  });

  it("consistent needs 3 matches and a spread within 25 percent", () => {
    const steady = [20, 21, 19].map((t, i) =>
      entry(1111, i + 1, { teleopFuelScored: t }),
    );
    const wild = [5, 40, 10].map((t, i) =>
      entry(2222, i + 1, { teleopFuelScored: t }),
    );
    const short = [20, 20].map((t, i) =>
      entry(3333, i + 1, { teleopFuelScored: t }),
    );
    const r = run([...steady, ...wild, ...short], [1111, 2222, 3333]);
    expect(teamsOf(r, "consistent")).toEqual([1111]);
  });

  it("no pit data and the pit answers read the latest entry", () => {
    const r = run(
      [],
      [1111, 2222, 3333],
      [
        pit(1111, { trenchFit: true, shootsWhileMoving: "true" }),
        pit(2222, { trenchFit: false }),
      ],
    );
    expect(teamsOf(r, "trench")).toEqual([1111]);
    expect(teamsOf(r, "moving")).toEqual([1111]);
    expect(teamsOf(r, "nopit")).toEqual([3333]);
  });
});

describe("combining", () => {
  it("requires every active filter", () => {
    const r = run(
      [
        entry(1111, 1, { eHigh: "Successful", tRdefense: true }),
        entry(1111, 2, { tRdefense: true }),
        entry(2222, 1, { eHigh: "Successful" }),
      ],
      [1111, 2222],
    );
    expect(passes(r, 1111, ["l3", "defense"])).toBe(true);
    expect(passes(r, 2222, ["l3", "defense"])).toBe(false);
    expect(passes(r, 2222, [])).toBe(true);
    expect(countOf(r, "l3")).toBe(2);
    expect(r.total).toBe(2);
  });

  it("covers 10 filters in 3 groups and parses the address", () => {
    expect(filterDefs).toHaveLength(10);
    expect(filterGroups).toHaveLength(3);
    expect(parseFilters("defense,bogus,l3,defense")).toEqual(["l3", "defense"]);
    expect(parseFilters(null)).toEqual([]);
  });
});
