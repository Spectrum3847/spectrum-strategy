import { describe, expect, it } from "vitest";
import type { EventEntry } from "../data/parse";
import { entriesBefore, entriesIn } from "./prior";

const entry = (
  id: string,
  key: string | null,
  values: Record<string, unknown> = {},
): EventEntry => ({
  id,
  teamNumber: 1111,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

describe("entriesBefore", () => {
  const entries = [
    entry("a", "2027test_qm1"),
    entry("b", "2027test_qm3"),
    entry("c", "2027test_qm4"),
    entry("d", "2027test_sf1m1"),
  ];

  it("keeps only the matches before this one", () => {
    expect(entriesBefore(entries, "2027test_qm3").map((e) => e.id)).toEqual([
      "a",
    ]);
    expect(entriesBefore(entries, "2027test_sf1m1").map((e) => e.id)).toEqual([
      "a",
      "b",
      "c",
    ]);
  });

  it("places a typed match number as a qualification match", () => {
    const typed = [
      entry("t2", null, { matchNumber: "2" }),
      entry("t5", null, { matchNumber: "5" }),
    ];
    expect(entriesBefore(typed, "2027test_qm4").map((e) => e.id)).toEqual([
      "t2",
    ]);
  });

  it("leaves out an entry that cannot be placed", () => {
    expect(entriesBefore([entry("x", null)], "2027test_qm9")).toEqual([]);
  });
});

describe("entriesIn", () => {
  it("keeps the entries of exactly this match", () => {
    const entries = [entry("a", "2027test_qm1"), entry("b", "2027test_QM2")];
    expect(entriesIn(entries, "2027test_qm2").map((e) => e.id)).toEqual(["b"]);
  });
});
