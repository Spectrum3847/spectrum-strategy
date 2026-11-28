import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { parseAssignments, parseTeamList } from "./assignments";
import {
  addColumn,
  addItem,
  addItems,
  exportText,
  moveColumn,
  moveItem,
  parsePasted,
  removeColumn,
  removeItem,
  renameColumn,
  renameItem,
  toDoc,
  withColumns,
} from "./edit";

const cols = () => [
  { key: "a", name: "Defense", items: ["Scout A", "Scout B"] },
  { key: "b", name: "Auto", items: ["Scout C"] },
];

describe("column edits", () => {
  it("adds a trimmed column and ignores a blank name", () => {
    expect(addColumn(cols(), "c", "  Climb ").at(-1)).toEqual({
      key: "c",
      name: "Climb",
      items: [],
    });
    expect(addColumn(cols(), "c", "   ")).toEqual(cols());
  });

  it("renames, and keeps the old name for a blank one", () => {
    expect(renameColumn(cols(), "a", " Pushing ")[0]?.name).toBe("Pushing");
    expect(renameColumn(cols(), "a", " ")).toEqual(cols());
  });

  it("removes a column by key", () => {
    expect(removeColumn(cols(), "a").map((c) => c.key)).toEqual(["b"]);
  });

  it("moves a column and stops at the ends", () => {
    expect(moveColumn(cols(), "b", -1).map((c) => c.key)).toEqual(["b", "a"]);
    expect(moveColumn(cols(), "a", 1).map((c) => c.key)).toEqual(["b", "a"]);
    expect(moveColumn(cols(), "a", -1)).toEqual(cols());
    expect(moveColumn(cols(), "b", 1)).toEqual(cols());
    expect(moveColumn(cols(), "zz", 1)).toEqual(cols());
  });
});

describe("item edits", () => {
  it("adds a trimmed entry and ignores a blank one", () => {
    expect(addItem(cols(), "b", " Scout D ")[1]?.items).toEqual([
      "Scout C",
      "Scout D",
    ]);
    expect(addItem(cols(), "b", "")).toEqual(cols());
  });

  it("adds a pasted list without repeating what the column holds", () => {
    expect(
      addItems(cols(), "a", ["scout a", "Scout D", "SCOUT d", " "])[0]?.items,
    ).toEqual(["Scout A", "Scout B", "Scout D"]);
  });

  it("renames, removes and moves an entry by position", () => {
    expect(renameItem(cols(), "a", 1, " Scout X ")[0]?.items).toEqual([
      "Scout A",
      "Scout X",
    ]);
    expect(renameItem(cols(), "a", 1, "")).toEqual(cols());
    expect(removeItem(cols(), "a", 0)[0]?.items).toEqual(["Scout B"]);
    expect(moveItem(cols(), "a", 1, -1)[0]?.items).toEqual([
      "Scout B",
      "Scout A",
    ]);
    expect(moveItem(cols(), "a", 0, -1)).toEqual(cols());
    expect(moveItem(cols(), "a", 5, 1)).toEqual(cols());
  });
});

describe("parsePasted", () => {
  it("splits on newlines, tabs, commas and semicolons", () => {
    expect(parsePasted("1111\n2222,\t3333; 1111\r\n\n 4444 ")).toEqual([
      "1111",
      "2222",
      "3333",
      "4444",
    ]);
    expect(parsePasted("Scout A, scout a")).toEqual(["Scout A"]);
    expect(parsePasted(" \n ")).toEqual([]);
  });
});

describe("toDoc", () => {
  const author = { uid: "u1", displayName: "Lead A" };
  const now = new Date("2027-03-05T18:04:05.123Z");

  it("writes the stored assignments document", () => {
    const table = withColumns(parseAssignments(null), cols(), author, now);
    expect(toDoc("assignments", table)).toEqual({
      columns: [
        { key: "a", name: "Defense", names: ["Scout A", "Scout B"] },
        { key: "b", name: "Auto", names: ["Scout C"] },
      ],
      authorUid: "u1",
      authorDisplayName: "Lead A",
      updatedAt: "2027-03-05T18:04:05.123Z",
      updatedAtTs: Timestamp.fromDate(now),
    });
  });

  it("writes the team list with its title and a teams key", () => {
    const table = {
      ...withColumns(
        parseTeamList(null),
        [{ key: "x", name: "Defense", items: ["1111"] }],
        author,
        now,
      ),
      title: "Pit list",
    };
    const doc = toDoc("teamList", table);
    expect(doc.title).toBe("Pit list");
    expect(doc.columns).toEqual([
      { key: "x", name: "Defense", teams: ["1111"] },
    ]);
    expect(Object.keys(doc).sort()).toEqual([
      "authorDisplayName",
      "authorUid",
      "columns",
      "title",
      "updatedAt",
      "updatedAtTs",
    ]);
  });

  it("round trips through the readers", () => {
    const table = withColumns(parseAssignments(null), cols(), author, now);
    expect(parseAssignments(toDoc("assignments", table)).columns).toEqual(
      cols(),
    );
  });
});

describe("exportText", () => {
  it("matches the copied text", () => {
    const a = parseAssignments({
      columns: [
        { key: "a", name: "Defense", names: ["Scout A", "Scout B"] },
        { key: "b", name: "Auto", names: [] },
      ],
    });
    const t = parseTeamList({
      title: "Pit list",
      columns: [{ key: "x", name: "Defense", teams: ["1111", "2222"] }],
    });
    expect(exportText(a, t)).toBe(
      [
        "T-Rex assignments",
        "",
        "Defense",
        "-------",
        "Scout A",
        "Scout B",
        "",
        "Auto",
        "----",
        "(unassigned)",
        "",
        "Pit list",
        "",
        "Defense",
        "-------",
        "1111",
        "2222",
        "",
        "Total teams: 2",
      ].join("\n"),
    );
  });

  it("says when a table is empty", () => {
    expect(exportText(parseAssignments(null), parseTeamList(null))).toBe(
      "T-Rex assignments\n(no traits added yet)\n\nTeam assignments\n(no columns added yet)",
    );
  });
});
