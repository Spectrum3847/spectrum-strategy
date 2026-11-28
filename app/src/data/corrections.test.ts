import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import {
  correctionDoc,
  maxCorrectedText,
  maxCorrectionNote,
  maxHistory,
  nextCorrection,
  parseCorrection,
} from "./corrections";

const author = { uid: "u1", displayName: "Lead A" };

describe("entry corrections", () => {
  it("reads the timestamp first and the ISO string as a fallback", () => {
    const base = {
      eventKey: "2027test",
      fields: { fuel: 12 },
      note: "Video",
      authorUid: "u1",
      authorDisplayName: "Lead A",
      updatedAt: "2027-03-01T10:00:00.000Z",
    };
    expect(parseCorrection("e1", base).updatedMs).toBe(
      Date.parse("2027-03-01T10:00:00.000Z"),
    );
    expect(
      parseCorrection("e1", { ...base, updatedAtTs: Timestamp.fromMillis(7) })
        .updatedMs,
    ).toBe(7);
    expect(parseCorrection("e1", { ...base, updatedAt: "bad" }).updatedMs).toBe(
      0,
    );
  });

  it("keeps only string, number and boolean values", () => {
    const parsed = parseCorrection("e1", {
      fields: {
        a: 1,
        b: "x",
        c: true,
        d: { x: 1 },
        e: [1],
        f: null,
        g: Number.NaN,
      },
    });
    expect(parsed.fields).toEqual({ a: 1, b: "x", c: true });
  });

  it("reads a document with the wrong shapes as empty", () => {
    expect(parseCorrection("e1", { fields: "x", note: 3 })).toMatchObject({
      id: "e1",
      fields: {},
      note: "",
      eventKey: "",
    });
  });

  it("never stamps behind the revision it replaces", () => {
    const prev = parseCorrection("e1", {
      updatedAtTs: Timestamp.fromMillis(5000),
    });
    expect(
      nextCorrection(prev, "e1", "2027test", {}, "", author, 4000).updatedMs,
    ).toBe(5000);
    expect(
      nextCorrection(prev, "e1", "2027test", {}, "", author, 6000).updatedMs,
    ).toBe(6000);
    expect(
      nextCorrection(null, "e1", "2027test", {}, "", author, 6000).updatedMs,
    ).toBe(6000);
  });

  it("caps the note and text values, and trims the note", () => {
    const next = nextCorrection(
      null,
      "e1",
      "2027test",
      { comments: "x".repeat(maxCorrectedText + 5), fuel: 3 },
      `  ${"y".repeat(maxCorrectionNote + 5)}`,
      { uid: "u1", displayName: "n".repeat(200) },
      1,
    );
    expect((next.fields.comments as string).length).toBe(maxCorrectedText);
    expect(next.fields.fuel).toBe(3);
    expect(next.note.length).toBe(maxCorrectionNote);
    expect(next.authorDisplayName.length).toBe(128);
  });

  it("writes exactly the keys the rules accept", () => {
    const doc = correctionDoc(
      nextCorrection(null, "e1", "2027test", { fuel: 3 }, "why", author, 1234),
    );
    expect(Object.keys(doc).sort()).toEqual(
      [
        "entryId",
        "eventKey",
        "fields",
        "note",
        "authorUid",
        "authorDisplayName",
        "history",
        "updatedAt",
        "updatedAtTs",
      ].sort(),
    );
    expect(doc.entryId).toBe("e1");
    expect(doc.updatedAt).toBe(new Date(1234).toISOString());
    expect((doc.updatedAtTs as Timestamp).toMillis()).toBe(1234);
  });

  it("reads history entries and skips malformed ones", () => {
    const good = {
      at: 5,
      by: "Lead A",
      uid: "u1",
      how: "table",
      field: "fuel",
      from: 1,
      to: 2,
    };
    const parsed = parseCorrection("e1", {
      history: [
        good,
        { ...good, how: "bogus" },
        { ...good, at: "x" },
        { ...good, to: { a: 1 } },
        "nope",
      ],
    });
    expect(parsed.history).toEqual([good]);
    expect(parseCorrection("e1", { history: "x" }).history).toEqual([]);
    expect(parseCorrection("e1", {}).history).toEqual([]);
  });

  it("keeps the earlier history when saved without a new one, and caps it", () => {
    const entry = (n: number) => ({
      at: n,
      by: "A",
      uid: "u1",
      how: "form" as const,
      field: "f",
      from: n,
      to: n + 1,
    });
    const prev = nextCorrection(null, "e1", "2027test", {}, "", author, 1, [
      entry(1),
    ]);
    const next = nextCorrection(prev, "e1", "2027test", {}, "", author, 2);
    expect(next.history).toEqual([entry(1)]);
    const many = Array.from({ length: maxHistory + 3 }, (_, i) => entry(i));
    expect(
      nextCorrection(null, "e1", "2027test", {}, "", author, 1, many).history,
    ).toHaveLength(maxHistory);
  });
});
