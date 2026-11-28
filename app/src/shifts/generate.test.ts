import { describe, expect, it } from "vitest";
import type { ShiftRotation } from "../scout/credit";
import { buildRotations, maxMatchCount } from "./generate";

const roster = (n: number) =>
  Array.from({ length: n }, (_, i) => ({ uid: `u${i}`, name: `Scout ${i}` }));

const cells = (rotations: ShiftRotation[]) =>
  rotations.map((r) =>
    r.blocks.map((b) => `${b.startMatch}-${b.endMatch} ${b.station}`),
  );

const red = (...cellsPainted: Array<[number, number]>) => {
  const out = new Map<number, Set<number>>();
  for (const [col, match] of cellsPainted) {
    out.set(col, (out.get(col) ?? new Set()).add(match));
  }
  return out;
};

describe("buildRotations without red cells", () => {
  it("rotates two groups of six, one station further each block", () => {
    expect(cells(buildRotations(18, roster(12)))).toEqual([
      ["1-6 R1", "13-18 R2"],
      ["1-6 R2", "13-18 R3"],
      ["1-6 R3", "13-18 B1"],
      ["1-6 B1", "13-18 B2"],
      ["1-6 B2", "13-18 B3"],
      ["1-6 B3", "13-18 R1"],
      ["7-12 R1"],
      ["7-12 R2"],
      ["7-12 R3"],
      ["7-12 B1"],
      ["7-12 B2"],
      ["7-12 B3"],
    ]);
  });

  it("merges one group's back-to-back blocks into one shift", () => {
    expect(cells(buildRotations(14, roster(6)))).toEqual([
      ["1-14 R1"],
      ["1-14 R2"],
      ["1-14 R3"],
      ["1-14 B1"],
      ["1-14 B2"],
      ["1-14 B3"],
    ]);
  });

  it("gives a short tail group fewer people and extends the last block", () => {
    expect(cells(buildRotations(20, roster(8)))).toEqual([
      ["1-6 R1", "13-20 R2"],
      ["1-6 R2", "13-20 R3"],
      ["1-6 R3", "13-20 B1"],
      ["1-6 B1", "13-20 B2"],
      ["1-6 B2", "13-20 B3"],
      ["1-6 B3", "13-20 R1"],
      ["7-12 R1"],
      ["7-12 R2"],
    ]);
  });

  it("leaves the second group out when only one round fits", () => {
    expect(cells(buildRotations(9, roster(12)))).toEqual([
      ["1-9 R1"],
      ["1-9 R2"],
      ["1-9 R3"],
      ["1-9 B1"],
      ["1-9 B2"],
      ["1-9 B3"],
      [],
      [],
      [],
      [],
      [],
      [],
    ]);
  });

  it("covers an event shorter than one shift with group 0", () => {
    expect(cells(buildRotations(4, roster(3)))).toEqual([
      ["1-4 R1"],
      ["1-4 R2"],
      ["1-4 R3"],
    ]);
  });

  it("steps a station per block it had, across three groups", () => {
    expect(cells(buildRotations(36, roster(18)))).toEqual([
      ["1-6 R1", "19-24 R2"],
      ["1-6 R2", "19-24 R3"],
      ["1-6 R3", "19-24 B1"],
      ["1-6 B1", "19-24 B2"],
      ["1-6 B2", "19-24 B3"],
      ["1-6 B3", "19-24 R1"],
      ["7-12 R1", "25-30 R2"],
      ["7-12 R2", "25-30 R3"],
      ["7-12 R3", "25-30 B1"],
      ["7-12 B1", "25-30 B2"],
      ["7-12 B2", "25-30 B3"],
      ["7-12 B3", "25-30 R1"],
      ["13-18 R1", "31-36 R2"],
      ["13-18 R2", "31-36 R3"],
      ["13-18 R3", "31-36 B1"],
      ["13-18 B1", "31-36 B2"],
      ["13-18 B2", "31-36 B3"],
      ["13-18 B3", "31-36 R1"],
    ]);
  });

  it("keeps each scouter's uid on their rotation", () => {
    expect(buildRotations(6, roster(2)).map((r) => r.uid)).toEqual([
      "u0",
      "u1",
    ]);
  });

  it("gives nothing for no roster or no matches", () => {
    expect(buildRotations(18, [])).toEqual([]);
    expect(buildRotations(0, roster(6))).toEqual([]);
    expect(buildRotations(-3, roster(6))).toEqual([]);
  });

  it("refuses a match count past the rules' cap", () => {
    expect(() => buildRotations(maxMatchCount + 1, roster(6))).toThrow();
    expect(cells(buildRotations(maxMatchCount, roster(6)))[5]).toEqual([
      "1-999 B3",
    ]);
  });
});

describe("buildRotations around red cells", () => {
  it("skips the red scouter's round and brings in the longest rested", () => {
    expect(cells(buildRotations(12, roster(8), red([0, 3])))).toEqual([
      ["7-12 R1"],
      ["1-6 R1", "7-12 R3"],
      ["1-6 R2", "7-12 B1"],
      ["1-6 R3", "7-12 B2"],
      ["1-6 B1", "7-12 B3"],
      ["1-6 B2"],
      ["1-6 B3"],
      ["7-12 R2"],
    ]);
  });

  it("extends the last round through the tail", () => {
    expect(cells(buildRotations(8, roster(7), red([1, 2])))).toEqual([
      ["1-8 R1"],
      [],
      ["1-8 R2"],
      ["1-8 R3"],
      ["1-8 B1"],
      ["1-8 B2"],
      ["1-8 B3"],
    ]);
  });

  it("picks a short event's scouters from whoever is free", () => {
    expect(cells(buildRotations(4, roster(4), red([0, 2])))).toEqual([
      [],
      ["1-4 R1"],
      ["1-4 R2"],
      ["1-4 R3"],
    ]);
  });

  it("moves each scouter to the station they have done least", () => {
    expect(cells(buildRotations(12, roster(6), red([0, 20])))).toEqual([
      ["1-6 R1", "7-12 R2"],
      ["1-6 R2", "7-12 R1"],
      ["1-6 R3", "7-12 B1"],
      ["1-6 B1", "7-12 R3"],
      ["1-6 B2", "7-12 B3"],
      ["1-6 B3", "7-12 B2"],
    ]);
  });
});
