import { describe, expect, it } from "vitest";
import type { Correction, HistoryEntry } from "../data/corrections";
import {
  appendHistory,
  diffFields,
  editInfo,
  historyList,
  stamp,
} from "./history";

const change = (over: Partial<HistoryEntry> = {}): HistoryEntry => ({
  at: 1000,
  by: "Lead A",
  uid: "u1",
  how: "table",
  field: "fuel",
  from: 10,
  to: 12,
  ...over,
});

const correction = (over: Partial<Correction> = {}): Correction => ({
  id: "a",
  eventKey: "2027test",
  fields: { fuel: 12 },
  note: "",
  authorUid: "u1",
  authorDisplayName: "Lead A",
  history: [],
  updatedMs: 500,
  ...over,
});

describe("diffFields", () => {
  it("lists only the fields whose value differs", () => {
    expect(diffFields({ a: 1, b: "x" }, { a: 2, b: "x" }, ["a", "b"])).toEqual([
      { field: "a", from: 1, to: 2 },
    ]);
  });

  it("treats a missing value as blank and ignores 5 versus '5'", () => {
    expect(diffFields({ a: 5 }, { a: "5" }, ["a"])).toEqual([]);
    expect(diffFields({}, { a: 3 }, ["a"])).toEqual([
      { field: "a", from: "", to: 3 },
    ]);
  });

  it("lists a field once when named twice", () => {
    expect(diffFields({ a: 1 }, { a: 2 }, ["a", "a"])).toHaveLength(1);
  });
});

describe("stamp and append", () => {
  it("stamps who, when and how on each change", () => {
    const [one] = stamp(
      [{ field: "a", from: 1, to: 2 }],
      "undo",
      {
        uid: "u9",
        displayName: "Lead Z",
      },
      77,
    );
    expect(one).toEqual({
      field: "a",
      from: 1,
      to: 2,
      at: 77,
      by: "Lead Z",
      uid: "u9",
      how: "undo",
    });
  });

  it("keeps the newest 200 changes", () => {
    const old = Array.from({ length: 200 }, (_, i) => change({ at: i }));
    const out = appendHistory(old, [change({ at: 999 })]);
    expect(out).toHaveLength(200);
    expect(out.at(-1)?.at).toBe(999);
    expect(out[0]?.at).toBe(1);
  });
});

describe("editInfo", () => {
  it("names the last change to the field", () => {
    const c = correction({
      history: [
        change({ at: 1, by: "Lead A" }),
        change({ at: 2, by: "Lead B" }),
      ],
    });
    expect(editInfo(c, "fuel")).toEqual({
      by: "Lead B",
      atMs: 2,
      how: "table",
    });
  });

  it("falls back to the document's author for a correction with no history", () => {
    expect(editInfo(correction(), "fuel")).toEqual({
      by: "Lead A",
      atMs: 500,
      how: "form",
    });
    expect(editInfo(correction(), "other")).toBeNull();
    expect(editInfo(null, "fuel")).toBeNull();
  });
});

describe("historyList", () => {
  it("lists newest first", () => {
    const c = correction({
      history: [change({ at: 1 }), change({ at: 2, from: 12, to: 14 })],
    });
    expect(
      historyList(c, ["fuel"], { fuel: 10 }, { fuel: 14 }).map((h) => h.at),
    ).toEqual([2, 1]);
  });

  it("adds an entry for a corrected field the history never recorded", () => {
    const list = historyList(
      correction(),
      ["fuel"],
      { fuel: 10 },
      { fuel: 12 },
    );
    expect(list).toEqual([
      expect.objectContaining({
        field: "fuel",
        from: 10,
        to: 12,
        by: "Lead A",
      }),
    ]);
  });

  it("is empty with no correction", () => {
    expect(historyList(null, [], {}, {})).toEqual([]);
  });
});
