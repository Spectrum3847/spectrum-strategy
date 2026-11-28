import { arrayRemove, arrayUnion, Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { decodeData, encodeData, removeOf, unionOf } from "./serialize";

describe("serialize", () => {
  it("round-trips a Timestamp through JSON", () => {
    const data = { at: new Timestamp(1700000000, 5), n: 3, list: [1, "a"] };
    const stored = JSON.parse(JSON.stringify(encodeData(data)));
    const back = decodeData(stored) as typeof data;
    expect(back.at).toBeInstanceOf(Timestamp);
    expect(back.at.isEqual(data.at)).toBe(true);
    expect(back.n).toBe(3);
    expect(back.list).toEqual([1, "a"]);
  });

  it("keeps the empty payload of a delete through JSON", () => {
    const stored = JSON.parse(JSON.stringify(encodeData({})));
    expect(decodeData(stored)).toEqual({});
  });

  it("turns a Date into a Timestamp and drops undefined fields", () => {
    const stored = encodeData({ d: new Date(2000), skip: undefined });
    expect(stored).toEqual({ d: { __ts: [2, 0] } });
  });

  it("keeps array edits through JSON and decodes them to Firestore's", () => {
    const stored = JSON.parse(
      JSON.stringify(
        encodeData({ photoKeys: unionOf(["a.jpg", "b.jpg"]), n: 1 }),
      ),
    );
    expect(stored.photoKeys).toEqual({
      __op: "arrayUnion",
      values: ["a.jpg", "b.jpg"],
    });
    const back = decodeData(stored) as Record<
      string,
      { isEqual(o: unknown): boolean }
    >;
    expect(back.photoKeys?.isEqual(arrayUnion("a.jpg", "b.jpg"))).toBe(true);
    const gone = decodeData(
      JSON.parse(JSON.stringify(encodeData(removeOf(["a.jpg"])))),
    );
    expect(
      (gone as { isEqual(o: unknown): boolean }).isEqual(arrayRemove("a.jpg")),
    ).toBe(true);
  });

  it("leaves a plain object that only looks like an edit alone", () => {
    const plain = { __op: "arrayUnion", values: [1], extra: true };
    expect(decodeData(encodeData(plain))).toEqual(plain);
    const other = { __op: "sum", values: [1] };
    expect(decodeData(encodeData(other))).toEqual(other);
  });
});
