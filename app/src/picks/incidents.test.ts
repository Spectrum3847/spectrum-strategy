import { describe, expect, it } from "vitest";
import type { EventEntry } from "../data/parse";
import {
  describe as describeIncidents,
  entryIncidents,
  incidentsByTeam,
  suggestions,
  suggestsDoNotPick,
  weight,
} from "./incidents";

let n = 0;
const entry = (
  team: number,
  key: string | null,
  values: Record<string, unknown>,
): EventEntry => ({
  id: `e${n++}`,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

describe("incidentsByTeam", () => {
  it("counts a match once, at the worse card", () => {
    const found = incidentsByTeam([
      entry(1111, "2027test_qm16", { ryCard: "Yellow" }),
      entry(1111, "2027test_qm16", { ryCard: "Red" }),
      entry(1111, "2027test_qm40", { ryCard: "Yellow" }),
      entry(1111, "2027test_qm55", { dieCard: true }),
      entry(1111, "2027test_qm74", { dieCard: "true" }),
    ]).get(1111);
    expect(found).toEqual({
      red: ["Q16"],
      yellow: ["Q40"],
      unknown: [],
      died: ["Q55", "Q74"],
    });
    expect(
      describeIncidents(
        found ?? { red: [], yellow: [], unknown: [], died: [] },
      ),
    ).toBe("Red card Q16 · yellow card Q40 · died Q55, Q74");
  });

  it("reads a card with no color as unknown, and a typed match number as a qual", () => {
    const found = incidentsByTeam([
      entry(2222, null, { ryCard: true, matchNumber: 7 }),
      entry(2222, "2027test_qm7", { dieCard: true }),
    ]).get(2222);
    expect(found).toEqual({
      red: [],
      yellow: [],
      unknown: ["Q7"],
      died: ["Q7"],
    });
  });

  it("leaves out teams with none and says when no match is named", () => {
    const found = incidentsByTeam([
      entry(3333, "2027test_qm1", { ryCard: "None", dieCard: false }),
      entry(4444, null, { dieCard: true }),
    ]);
    expect(found.has(3333)).toBe(false);
    expect(found.get(4444)?.died).toEqual(["(no match number)"]);
  });
});

describe("suggestions", () => {
  const incidents = incidentsByTeam([
    entry(1111, "2027test_qm1", { ryCard: "Red" }),
    entry(2222, "2027test_qm1", { dieCard: true }),
    entry(3333, "2027test_qm1", { dieCard: true }),
    entry(3333, "2027test_qm2", { dieCard: true }),
    entry(4444, "2027test_qm1", { ryCard: "Yellow" }),
    entry(4444, "2027test_qm2", { dieCard: true }),
  ]);

  it("weighs a red card as three", () => {
    expect(
      weight(
        incidents.get(1111) ?? { red: [], yellow: [], unknown: [], died: [] },
      ),
    ).toBe(3);
  });

  it("suggests a red card or two incidents, worst first, one death alone is not enough", () => {
    expect(suggestions(incidents, new Set(), null).map((s) => s.team)).toEqual([
      1111, 3333, 4444,
    ]);
    expect(
      suggestsDoNotPick(
        incidents.get(2222) ?? { red: [], yellow: [], unknown: [], died: [] },
      ),
    ).toBe(false);
  });

  it("leaves out listed teams and our own", () => {
    expect(
      suggestions(incidents, new Set([1111]), 3333).map((s) => s.team),
    ).toEqual([4444]);
  });
});

describe("entryIncidents", () => {
  it("names one entry's card and death", () => {
    expect(entryIncidents({ ryCard: "Yellow", dieCard: true })).toBe(
      "Yellow card, died",
    );
    expect(entryIncidents({ ryCard: "Red" })).toBe("Red card");
    expect(entryIncidents({ ryCard: true })).toBe("Card");
    expect(entryIncidents({ dieCard: "true" })).toBe("Died");
  });

  it("is empty with no card and no death", () => {
    expect(entryIncidents({ ryCard: "None", dieCard: false })).toBe("");
    expect(entryIncidents({})).toBe("");
  });
});
