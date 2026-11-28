import { describe, expect, it } from "vitest";
import type { Correction } from "../data/corrections";
import { applyCorrections } from "./apply";

const entry = (id: string, fieldValues: Record<string, unknown>) => ({
  id,
  fieldValues,
});

const correction = (
  id: string,
  fields: Record<string, unknown>,
  over: Partial<Correction> = {},
): Correction => ({
  id,
  eventKey: "2027test",
  fields,
  note: "",
  authorUid: "u1",
  authorDisplayName: "Lead A",
  history: [],
  updatedMs: 1000,
  ...over,
});

describe("applyCorrections", () => {
  it("replaces corrected values and flags each corrected field", () => {
    const [out] = applyCorrections(
      [entry("a", { fuel: 10, defense: false, comments: "ok" })],
      [correction("a", { fuel: 14, defense: true })],
    );
    expect(out?.fieldValues).toEqual({
      fuel: 14,
      defense: true,
      comments: "ok",
    });
    expect(out?.corrected).toEqual(["fuel", "defense"]);
    expect(out?.correction?.authorDisplayName).toBe("Lead A");
  });

  it("keeps the raw values untouched", () => {
    const raw = { fuel: 10 };
    const [out] = applyCorrections(
      [entry("a", raw)],
      [correction("a", { fuel: 14 })],
    );
    expect(out?.rawValues).toBe(raw);
    expect(raw).toEqual({ fuel: 10 });
    expect(out?.rawValues.fuel).toBe(10);
  });

  it("leaves an entry with no correction as it was", () => {
    const [out] = applyCorrections(
      [entry("a", { fuel: 10 })],
      [correction("b", { fuel: 99 })],
    );
    expect(out?.fieldValues).toEqual({ fuel: 10 });
    expect(out?.corrected).toEqual([]);
    expect(out?.correction).toBeNull();
  });

  it("adds a value the scout left out", () => {
    const [out] = applyCorrections(
      [entry("a", {})],
      [correction("a", { comments: "Played defense" })],
    );
    expect(out?.fieldValues.comments).toBe("Played defense");
    expect(out?.corrected).toEqual(["comments"]);
  });

  it("does not flag a value that equals the scout's own", () => {
    const [out] = applyCorrections(
      [entry("a", { fuel: "10", defense: true })],
      [correction("a", { fuel: 10, defense: true })],
    );
    expect(out?.corrected).toEqual([]);
  });

  it("treats an emptied correction as none but keeps its stamp", () => {
    const [out] = applyCorrections(
      [entry("a", { fuel: 10 })],
      [correction("a", {}, { updatedMs: 5000 })],
    );
    expect(out?.fieldValues).toEqual({ fuel: 10 });
    expect(out?.corrected).toEqual([]);
    expect(out?.correction?.updatedMs).toBe(5000);
  });

  it("keeps any extra properties of the entry", () => {
    const [out] = applyCorrections(
      [{ id: "a", fieldValues: {}, teamNumber: 1111 }],
      [],
    );
    expect(out?.teamNumber).toBe(1111);
  });
});
