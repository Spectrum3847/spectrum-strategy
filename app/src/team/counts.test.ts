import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { parseConfig } from "../scout/config";
import { valueCounts } from "./counts";
import { groupByMatch, type StatInput } from "./stats";

const entry = (
  id: string,
  matchKey: string,
  fieldValues: Record<string, unknown>,
): StatInput => ({ id, matchKey, fieldValues });

const config = parseConfig({
  title: "T",
  sections: [
    {
      name: "Auto",
      fields: [
        {
          title: "Start Position",
          type: "select",
          code: "begin",
          choices: { L: "Left", C: "Center", R: "Right" },
        },
        {
          title: "Driver Station",
          type: "select",
          code: "robot",
          choices: { R1: "Red 1" },
        },
      ],
    },
    {
      name: "Notes",
      fields: [
        {
          title: "Tags",
          type: "multi-select",
          code: "tags",
          choices: { fast: "Fast", tipped: "Tipped over", slow: "Slow" },
        },
      ],
    },
  ],
});

describe("valueCounts", () => {
  it("counts a start position per match, most common first", () => {
    const groups = groupByMatch([
      entry("a", "x_qm1", { begin: "R" }),
      entry("b", "x_qm2", { begin: "L" }),
      entry("c", "x_qm3", { begin: "L" }),
      entry("d", "x_qm4", { begin: "C" }),
      entry("e", "x_qm5", { begin: "L" }),
    ]);
    const [row] = valueCounts(config, groups);
    expect(row?.label).toBe("Start Position");
    expect(row?.counts).toEqual([
      { label: "Left", count: 3 },
      { label: "Center", count: 1 },
      { label: "Right", count: 1 },
    ]);
  });

  it("does not count a category select that is not a start position", () => {
    const groups = groupByMatch([entry("a", "x_qm1", { robot: "R1" })]);
    expect(valueCounts(config, groups)).toEqual([]);
  });

  it("lets the scouts of one match vote, so the match counts once", () => {
    const groups = groupByMatch([
      entry("a", "x_qm1", { begin: "L" }),
      entry("b", "x_qm1", { begin: "R" }),
      entry("c", "x_qm1", { begin: "R" }),
    ]);
    expect(valueCounts(config, groups)[0]?.counts).toEqual([
      { label: "Right", count: 1 },
    ]);
  });

  it("counts a tag once per match when any scout chose it", () => {
    const groups = groupByMatch([
      entry("a", "x_qm1", { tags: "fast,tipped" }),
      entry("b", "x_qm1", { tags: "fast" }),
      entry("c", "x_qm2", { tags: "fast" }),
      entry("d", "x_qm3", { tags: "" }),
    ]);
    const tags = valueCounts(config, groups).find((r) => r.code === "tags");
    expect(tags?.counts).toEqual([
      { label: "Fast", count: 2 },
      { label: "Tipped over", count: 1 },
    ]);
  });

  it("reads the bundled config's starting position", () => {
    const rows = valueCounts(
      parseConfig(bundled),
      groupByMatch([entry("a", "x_qm1", { starting: "Center Hub" })]),
    );
    expect(rows.map((r) => r.label)).toEqual(["Robot Starting Position"]);
    expect(rows[0]?.counts).toEqual([{ label: "Center Hub", count: 1 }]);
  });

  it("returns nothing when no match answered", () => {
    expect(valueCounts(config, [])).toEqual([]);
  });
});
