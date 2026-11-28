import { describe, expect, it } from "vitest";
import {
  isAssignedTo,
  mergeSections,
  parseAssignments,
  parseTeamList,
  totalTeams,
} from "./assignments";

describe("parseAssignments", () => {
  it("reads stored columns", () => {
    const table = parseAssignments({
      columns: [
        { key: "a", name: "Defense", names: ["Scout A", " ", "Scout B", 3] },
        { key: "", name: "No key", names: ["x"] },
        { key: "b", name: 5, names: [] },
        { key: "c", name: "Auto" },
        "nope",
      ],
      authorDisplayName: " Lead A ",
      updatedAt: "2027-03-05T18:04:05.123Z",
    });
    expect(table.columns).toEqual([
      { key: "a", name: "Defense", items: ["Scout A", "Scout B"] },
      { key: "c", name: "Auto", items: [] },
    ]);
    expect(table.authorName).toBe("Lead A");
    expect(table.updatedAt).toBe("2027-03-05T18:04:05.123Z");
  });

  it("treats a missing document or wrong types as empty", () => {
    expect(parseAssignments(null).columns).toEqual([]);
    expect(parseAssignments({ columns: "x" }).columns).toEqual([]);
  });
});

describe("parseTeamList", () => {
  it("reads the title and each column's teams", () => {
    const table = parseTeamList({
      title: "Event list",
      columns: [{ key: "a", name: "Defense", teams: ["1111", "", "2222"] }],
    });
    expect(table.title).toBe("Event list");
    expect(table.columns).toEqual([
      { key: "a", name: "Defense", items: ["1111", "2222"] },
    ]);
    expect(totalTeams(table.columns)).toBe(2);
  });
});

describe("mergeSections", () => {
  const assignments = parseAssignments({
    columns: [
      { key: "1", name: "Defense", names: ["Scout A"] },
      { key: "2", name: "Autonomous", names: ["Scout B", "Scout C"] },
    ],
  }).columns;

  it("pairs team columns by trimmed, case-insensitive name", () => {
    const teams = parseTeamList({
      columns: [
        { key: "x", name: " autonomous ", teams: ["3333"] },
        { key: "y", name: "Defense", teams: ["1111", "2222"] },
      ],
    }).columns;
    expect(mergeSections(assignments, teams)).toEqual([
      {
        name: "Defense",
        scouters: ["Scout A"],
        teams: ["1111", "2222"],
        assignmentKey: "1",
        teamKey: "y",
      },
      {
        name: "Autonomous",
        scouters: ["Scout B", "Scout C"],
        teams: ["3333"],
        assignmentKey: "2",
        teamKey: "x",
      },
    ]);
  });

  it("keeps a trait with no team column and a team column with no trait", () => {
    const teams = parseTeamList({
      columns: [{ key: "z", name: "Climb", teams: ["4444"] }],
    }).columns;
    expect(mergeSections(assignments, teams)).toEqual([
      {
        name: "Defense",
        scouters: ["Scout A"],
        teams: [],
        assignmentKey: "1",
        teamKey: null,
      },
      {
        name: "Autonomous",
        scouters: ["Scout B", "Scout C"],
        teams: [],
        assignmentKey: "2",
        teamKey: null,
      },
      {
        name: "Climb",
        scouters: [],
        teams: ["4444"],
        assignmentKey: null,
        teamKey: "z",
      },
    ]);
  });

  it("uses each team column once", () => {
    const dup = [
      { key: "1", name: "Defense", items: ["A"] },
      { key: "2", name: "defense", items: ["B"] },
    ];
    const teams = [{ key: "t", name: "Defense", items: ["1111"] }];
    const merged = mergeSections(dup, teams);
    expect(merged[0]?.teams).toEqual(["1111"]);
    expect(merged[1]?.teams).toEqual([]);
  });
});

describe("isAssignedTo", () => {
  const section = {
    name: "Defense",
    scouters: ["Scout A"],
    teams: [],
    assignmentKey: "1",
    teamKey: null,
  };
  it("matches a name without regard to case or spaces", () => {
    expect(isAssignedTo(section, " scout a ")).toBe(true);
    expect(isAssignedTo(section, "Scout B")).toBe(false);
    expect(isAssignedTo(section, "")).toBe(false);
  });
});
