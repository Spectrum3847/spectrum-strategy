import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { emptyBoard, setCell } from "./board";
import {
  boardDoc,
  boardPath,
  isBlank,
  nextStamp,
  parseShared,
  sameBoard,
  takesRemote,
} from "./shared";

const board = setCell(
  emptyBoard(),
  { grid: "alliance", row: 0, column: 0 },
  "1111",
);

describe("shared board document", () => {
  it("is one document per event", () => {
    expect(boardPath("2027a")).toBe("playoffBoards/2027a");
  });

  it("writes only the keys the rules accept", () => {
    const doc = boardDoc("2027a", board, 1_700_000_000_000, "Scout A");
    expect(Object.keys(doc).sort()).toEqual([
      "alliance",
      "eventKey",
      "labels",
      "meeting",
      "styles",
      "updatedAt",
      "updatedAtTs",
      "updatedBy",
      "version",
    ]);
    expect(doc.updatedAt).toBe("2023-11-14T22:13:20.000Z");
    expect(doc.updatedAtTs).toEqual(Timestamp.fromMillis(1_700_000_000_000));
    expect(doc.alliance).toEqual({ "0,0": "1111" });
  });

  it("reads a document back", () => {
    const doc = boardDoc("2027a", board, 1_700_000_000_000, "Scout A");
    const read = parseShared(doc);
    expect(read.board).toEqual(board);
    expect(read.ms).toBe(1_700_000_000_000);
    expect(read.by).toBe("Scout A");
  });

  it("falls back to updatedAt without a timestamp, and to zero without either", () => {
    expect(parseShared({ updatedAt: "2023-11-14T22:13:20.000Z" }).ms).toBe(
      1_700_000_000_000,
    );
    expect(parseShared({}).ms).toBe(0);
    expect(parseShared({}).by).toBe("");
  });
});

describe("stamps and remote changes", () => {
  it("stamps with the later of now and what was seen", () => {
    expect(nextStamp(100, 50, 70)).toBe(100);
    expect(nextStamp(100, 150)).toBe(150);
  });

  it("takes a newer board only when nothing here is unsent", () => {
    expect(takesRemote({ heldMs: 1, remoteMs: 2, unsent: false })).toBe(true);
    expect(takesRemote({ heldMs: 1, remoteMs: 2, unsent: true })).toBe(false);
    expect(takesRemote({ heldMs: 2, remoteMs: 2, unsent: false })).toBe(false);
    expect(takesRemote({ heldMs: 3, remoteMs: 2, unsent: false })).toBe(false);
  });

  it("compares whole boards", () => {
    expect(isBlank(emptyBoard())).toBe(true);
    expect(isBlank(board)).toBe(false);
    expect(
      sameBoard(
        board,
        setCell(emptyBoard(), { grid: "alliance", row: 0, column: 0 }, "1111"),
      ),
    ).toBe(true);
  });
});
