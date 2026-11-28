import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { applyCorrections } from "../corrections/apply";
import type { EventEntry, FormEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import {
  cellOf,
  defaultSort,
  filterRows,
  matchRows,
  noFilters,
  recordFields,
  recordRows,
  scoutNames,
  sortRows,
} from "./rows";

const config = parseConfig(bundled);

const entry = (
  id: string,
  key: string | null,
  team: number,
  scout: string,
  values: Record<string, unknown> = {},
): EventEntry => ({
  id,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: scout,
  updatedAt: `2027-03-01T10:00:0${id.length}.000Z`,
  fieldValues: values,
});

const rows = matchRows(
  applyCorrections(
    [
      entry("a", "2027test_qm10", 3333, "Scout B"),
      entry("b", "2027test_qm2", 2222, "Scout A", { robot: "R2" }),
      entry("c", "2027test_sf1m1", 1111, ""),
      entry("d", null, 4444, "Scout A", { matchNumber: "5" }),
      entry("e", "2027test_qm2", 1111, "scout c"),
    ],
    [],
  ),
);

const ids = (r: { id: string }[]) => r.map((x) => x.id);

describe("matchRows", () => {
  it("names the card and death an entry recorded", () => {
    const [carded, clean] = matchRows(
      applyCorrections(
        [
          entry("a", "2027test_qm1", 1111, "Scout A", {
            ryCard: "Red",
            dieCard: true,
          }),
          entry("b", "2027test_qm1", 2222, "Scout A"),
        ],
        [],
      ),
    );
    expect(carded?.incidents).toBe("Red card, died");
    expect(clean?.incidents).toBe("");
  });

  it("labels, links and places entries", () => {
    const byId = new Map(rows.map((r) => [r.id, r]));
    expect(byId.get("a")).toMatchObject({
      label: "Q10",
      href: "2027test_qm10",
      number: 10,
    });
    expect(byId.get("b")).toMatchObject({ station: "R2" });
    expect(byId.get("c")).toMatchObject({ label: "SF1", number: null });
    expect(byId.get("d")).toMatchObject({
      label: "Match 5 (typed)",
      href: null,
      number: 5,
    });
  });
});

describe("sortRows", () => {
  it("orders by play order, typed numbers beside qualifications", () => {
    expect(ids(sortRows(rows, defaultSort("match")))).toEqual([
      "e",
      "b",
      "d",
      "a",
      "c",
    ]);
  });

  it("reverses", () => {
    expect(
      ids(sortRows(rows, { key: "match", reversed: true })).slice(0, 2),
    ).toEqual(["c", "a"]);
  });

  it("orders by team, then match", () => {
    expect(ids(sortRows(rows, { key: "team", reversed: false }))).toEqual([
      "e",
      "c",
      "b",
      "a",
      "d",
    ]);
  });

  it("orders by scout with blank names last", () => {
    const sorted = sortRows(rows, { key: "scout", reversed: false });
    expect(sorted.map((r) => r.scout)).toEqual([
      "Scout A",
      "Scout A",
      "Scout B",
      "scout c",
      "",
    ]);
  });
});

describe("filterRows", () => {
  it("filters by team prefix", () => {
    expect(ids(filterRows(rows, { ...noFilters, team: "11" }))).toEqual([
      "c",
      "e",
    ]);
    expect(ids(filterRows(rows, { ...noFilters, team: "frc2222" }))).toEqual([
      "b",
    ]);
  });

  it("filters by scout", () => {
    expect(ids(filterRows(rows, { ...noFilters, scout: "Scout A" }))).toEqual([
      "b",
      "d",
    ]);
  });

  it("filters by a qualification match range, ends included", () => {
    expect(ids(filterRows(rows, { ...noFilters, from: "2", to: "5" }))).toEqual(
      ["b", "d", "e"],
    );
    expect(ids(filterRows(rows, { ...noFilters, from: "10" }))).toEqual(["a"]);
    expect(ids(filterRows(rows, { ...noFilters, to: "1" }))).toEqual([]);
  });

  it("ignores a range that is not a number", () => {
    expect(filterRows(rows, { ...noFilters, from: "x" })).toHaveLength(5);
  });
});

describe("scoutNames", () => {
  it("lists each named scout once", () => {
    expect(scoutNames(rows)).toEqual(["Scout A", "Scout B", "scout c"]);
  });
});

describe("cellOf", () => {
  it("shows select labels and marks a corrected value", () => {
    const [row] = matchRows(
      applyCorrections(
        [entry("a", "2027test_qm1", 1111, "Scout A", { teleopFuelScored: 10 })],
        [
          {
            id: "a",
            eventKey: "2027test",
            fields: { teleopFuelScored: 30, tRdefense: true },
            note: "",
            authorUid: "u2",
            authorDisplayName: "Lead B",
            history: [],
            updatedMs: 1,
          },
        ],
      ),
    );
    if (!row) throw new Error("no row");
    const field = (code: string) => {
      const f = config.sections
        .flatMap((s) => s.fields)
        .find((x) => x.code === code);
      if (!f) throw new Error(code);
      return f;
    };
    expect(cellOf(field("teleopFuelScored"), row)).toEqual({
      text: "30",
      was: "10",
      edit: { by: "Lead B", atMs: 1, how: "form" },
    });
    expect(cellOf(field("tRdefense"), row)).toEqual({
      text: "Yes",
      was: "nothing",
      edit: { by: "Lead B", atMs: 1, how: "form" },
    });
    expect(cellOf(field("autoFuelScored"), row)).toEqual({
      text: "",
      was: null,
      edit: null,
    });
  });
});

describe("recordRows", () => {
  it("reads a pit record without correction", () => {
    const pit: FormEntry = {
      id: "p",
      teamNumber: 1111,
      eventKey: "2027test",
      fieldValues: {},
      authorUid: "u",
      scoutName: "Scout A",
      updatedAt: "2027-03-01T10:00:00.000Z",
    };
    const [row] = recordRows([pit]);
    expect(row).toMatchObject({
      team: 1111,
      event: "2027test",
      corrected: [],
      entry: null,
    });
    expect(recordFields(config).length).toBeGreaterThan(0);
  });
});
