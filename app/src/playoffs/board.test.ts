import { describe, expect, it } from "vitest";
import {
  clearCell,
  defaultLabels,
  emptyBoard,
  isCell,
  move,
  nextUp,
  parseBoard,
  placed,
  readingOrder,
  setCell,
  setLabel,
  setStyle,
  styleOf,
} from "./board";

const m = (row: number, column: number) => ({
  grid: "meeting" as const,
  row,
  column,
});
const a = (row: number, column: number) => ({
  grid: "alliance" as const,
  row,
  column,
});

describe("cells", () => {
  it("knows the grid shapes", () => {
    expect(isCell(m(12, 0))).toBe(true);
    expect(isCell(m(13, 0))).toBe(false);
    expect(isCell(m(13, 5))).toBe(true);
    expect(isCell(m(22, 5))).toBe(true);
    expect(isCell(m(23, 5))).toBe(false);
    expect(isCell(m(0, 6))).toBe(false);
    expect(isCell(a(7, 3))).toBe(true);
    expect(isCell(a(8, 0))).toBe(false);
    expect(isCell(a(0, 4))).toBe(false);
  });

  it("stores text sparsely and drops a blank cell", () => {
    let board = setCell(emptyBoard(), m(0, 0), "1111");
    expect(board.meeting).toEqual({ "0,0": "1111" });
    board = setCell(board, m(0, 0), "   ");
    expect(board.meeting).toEqual({});
  });

  it("ignores a cell outside the grid", () => {
    const board = emptyBoard();
    expect(setCell(board, m(13, 0), "1111")).toBe(board);
  });

  it("drops a style once it is plain again", () => {
    let board = setStyle(emptyBoard(), 0, 0, {
      highlighted: true,
      italic: false,
    });
    expect(styleOf(board, 0, 0).highlighted).toBe(true);
    board = setStyle(board, 0, 0, { highlighted: false, italic: false });
    expect(board.styles).toEqual({});
  });

  it("renames a column", () => {
    const board = setLabel(emptyBoard(), 2, "Maybe");
    expect(board.labels[2]).toBe("Maybe");
    expect(board.labels[0]).toBe("Tier 1");
  });
});

describe("move", () => {
  const base = () => {
    let board = setCell(emptyBoard(), m(0, 0), "1111");
    board = setStyle(board, 0, 0, { highlighted: true, italic: true });
    return setCell(board, m(0, 1), "2222");
  };

  it("moves a cell to an empty cell with its style", () => {
    const board = move(base(), { kind: "cell", ...m(0, 0) }, m(1, 3));
    expect(board.meeting).toEqual({ "0,1": "2222", "1,3": "1111" });
    expect(styleOf(board, 1, 3)).toEqual({ highlighted: true, italic: true });
    expect(board.styles["0,0"]).toBeUndefined();
  });

  it("swaps with a filled cell", () => {
    const board = move(base(), { kind: "cell", ...m(0, 0) }, m(0, 1));
    expect(board.meeting).toEqual({ "0,0": "2222", "0,1": "1111" });
    expect(styleOf(board, 0, 1).italic).toBe(true);
    expect(styleOf(board, 0, 0).italic).toBe(false);
  });

  it("puts a team from the list into an alliance cell", () => {
    const board = move(emptyBoard(), { kind: "team", team: 3333 }, a(0, 0));
    expect(board.alliance).toEqual({ "0,0": "3333" });
  });

  it("moves between the two grids without a style", () => {
    const board = move(base(), { kind: "cell", ...m(0, 0) }, a(2, 1));
    expect(board.alliance).toEqual({ "2,1": "1111" });
    expect(board.meeting["0,0"]).toBeUndefined();
    expect(board.styles["0,0"]).toBeUndefined();
  });

  it("leaves the board alone when dropped on itself", () => {
    const board = base();
    expect(move(board, { kind: "cell", ...m(0, 0) }, m(0, 0))).toBe(board);
  });

  it("clears a cell and its style", () => {
    const board = clearCell(base(), m(0, 0));
    expect(board.meeting).toEqual({ "0,1": "2222" });
    expect(board.styles).toEqual({});
  });
});

describe("next up", () => {
  const board = () => {
    let b = emptyBoard();
    b = setCell(b, m(0, 0), "1111");
    b = setCell(b, m(0, 1), "2222");
    b = setCell(b, m(0, 2), "note");
    b = setCell(b, m(1, 0), "3333");
    b = setCell(b, m(1, 1), "4444");
    b = setCell(b, m(13, 5), "5555");
    return b;
  };

  it("reads across a row, then down, with the long column last", () => {
    expect(readingOrder(board())).toEqual([1111, 2222, 3333, 4444, 5555]);
  });

  it("shows the first three teams not yet in an alliance", () => {
    expect(nextUp(board())).toEqual([1111, 2222, 3333]);
    const placedAny = setCell(board(), a(0, 1), " 2222 ");
    expect(placed(placedAny)).toEqual(new Set([2222]));
    expect(nextUp(placedAny)).toEqual([1111, 3333, 4444]);
  });

  it("lists a team once", () => {
    const b = setCell(board(), m(2, 0), "1111");
    expect(nextUp(b, 10)).toEqual([1111, 2222, 3333, 4444, 5555]);
  });
});

describe("parseBoard", () => {
  it("reads an empty or unreadable value as an empty board", () => {
    expect(parseBoard(null)).toEqual(emptyBoard());
    expect(parseBoard("x")).toEqual(emptyBoard());
  });

  it("keeps what is valid and drops what is not", () => {
    const board = parseBoard({
      version: 1,
      labels: ["Best", "", 4],
      meeting: { "0,0": "1111", "99,0": "9999", bad: "x", "1,1": "" },
      styles: { "0,0": { highlighted: true }, "1,1": {} },
      alliance: { "0,0": "2222", "9,9": "x" },
    });
    expect(board.labels).toEqual(["Best", ...defaultLabels.slice(1)]);
    expect(board.meeting).toEqual({ "0,0": "1111" });
    expect(board.styles).toEqual({
      "0,0": { highlighted: true, italic: false },
    });
    expect(board.alliance).toEqual({ "0,0": "2222" });
  });

  it("pads a five label board with the sixth default", () => {
    const board = parseBoard({ labels: ["A", "B", "C", "D", "E"] });
    expect(board.labels).toEqual(["A", "B", "C", "D", "E", "Tier 6"]);
  });
});
