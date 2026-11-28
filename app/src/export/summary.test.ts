import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { buildSummaryCsv, summaryFileName } from "./summary";

const config = parseConfig(bundled);

const entry = (
  id: string,
  match: number,
  team: number,
  fieldValues: Record<string, unknown>,
): EventEntry => ({
  id,
  tbaMatchKey: `2027test_qm${match}`,
  teamNumber: team,
  alliance: "Red",
  scoutName: "Scout A",
  updatedAt: "2027-03-05T18:00:00.000Z",
  fieldValues,
});

const entries = [
  entry("a", 1, 2222, {
    autoFuelScored: 4,
    teleopFuelScored: 10,
    eLow: "Successful",
  }),
  entry("b", 2, 2222, {
    autoFuelScored: 6,
    teleopFuelScored: 21,
    eLow: "Failed",
  }),
  entry("c", 1, 1111, { autoFuelScored: 2, teleopFuelScored: 3 }),
];

describe("buildSummaryCsv", () => {
  const lines = buildSummaryCsv(
    config,
    entries,
    [1111, 2222, 3333],
    "2027test",
  ).split("\r\n");
  const header = (lines[0] ?? "").split(",");
  const cell = (line: string, name: string) =>
    line.split(",")[header.indexOf(name)];

  it("starts with the fixed columns, then one climb column per field", () => {
    expect(header.slice(0, 7)).toEqual([
      "Event",
      "Team",
      "Matches",
      "IQM Teleop",
      "Max Teleop",
      "IQM Auto",
      "Max Auto",
    ]);
    expect(header).toContain("Low Climb (L1) success");
    expect(header).not.toContain("Climb Position success");
  });

  it("has one row per team in team order, with the event listed", () => {
    expect(lines).toHaveLength(4);
    expect(lines.slice(1).map((l) => l.split(",").slice(0, 2))).toEqual([
      ["2027test", "1111"],
      ["2027test", "2222"],
      ["2027test", "3333"],
    ]);
  });

  it("formats whole numbers plainly, others to one decimal, rates as percent", () => {
    const team2222 = lines[2] ?? "";
    expect(cell(team2222, "Matches")).toBe("2");
    expect(cell(team2222, "Max Teleop")).toBe("21");
    expect(cell(team2222, "IQM Teleop")).toBe("15.5");
    expect(cell(team2222, "Low Climb (L1) success")).toBe("50%");
  });

  it("leaves a team with no data blank instead of zero", () => {
    const blanks = Array(header.length - 3).fill("");
    expect(lines[3]).toBe(["2027test", "3333", "0", ...blanks].join(","));
  });
});

describe("summaryFileName", () => {
  it("slugs the event key", () => {
    expect(summaryFileName("2027TX Hou")).toBe("2027tx-hou-team-summary.csv");
    expect(summaryFileName("")).toBe("team-summary.csv");
  });
});
