import { describe, expect, it } from "vitest";
import type { EventEntry } from "../data/parse";
import { detectFlags, parseMatchNumber } from "./flags";

const entry = (
  id: string,
  key: string | null,
  team: number,
  values: Record<string, unknown> = {},
): EventEntry => ({
  id,
  tbaMatchKey: key,
  teamNumber: team,
  alliance: "Red",
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

describe("parseMatchNumber", () => {
  it("reads bare numbers, labels and TBA keys", () => {
    expect(parseMatchNumber("12")).toEqual({ level: null, number: 12 });
    expect(parseMatchNumber("Q12")).toEqual({ level: "qm", number: 12 });
    expect(parseMatchNumber("Match 12")).toEqual({ level: "qm", number: 12 });
    expect(parseMatchNumber("2027test_qm12")).toEqual({
      level: "qm",
      number: 12,
    });
    expect(parseMatchNumber("2027test_sf2m3")).toEqual({
      level: "sf",
      number: 3,
    });
  });

  it("reads nothing from text with no number or from a uuid", () => {
    expect(parseMatchNumber("")).toBeNull();
    expect(parseMatchNumber("a1b2c3d4-5678-90ab")).toBeNull();
  });
});

describe("detectFlags", () => {
  it("flags two rows on one team in a match", () => {
    const flags = detectFlags([
      entry("a", "2027test_qm1", 1111),
      entry("b", "2027test_qm1", 1111),
      entry("c", "2027test_qm1", 2222),
    ]);
    expect(flags.get("a")?.[0]).toMatchObject({
      kind: "team",
      reason: "Team 1111 is on 2 rows in Q1.",
    });
    expect(flags.has("b")).toBe(true);
    expect(flags.has("c")).toBe(false);
  });

  it("flags two rows on one driver station", () => {
    const flags = detectFlags([
      entry("a", "2027test_qm1", 1111, { station: "Red 1" }),
      entry("b", "2027test_qm1", 2222, { station: "R1" }),
      entry("c", "2027test_qm2", 3333, { station: "R1" }),
    ]);
    expect(flags.get("a")?.[0]?.kind).toBe("station");
    expect(flags.get("b")?.[0]?.reason).toBe(
      "Driver station R1 is on 2 rows in Q1.",
    );
    expect(flags.has("c")).toBe(false);
  });

  it("ignores an entry with no team", () => {
    const flags = detectFlags([
      entry("a", "2027test_qm1", 0),
      entry("b", "2027test_qm1", 0),
    ]);
    expect(flags.size).toBe(0);
  });

  it("flags a typed number that disagrees with the saved match", () => {
    const flags = detectFlags([
      entry("a", "2027test_qm5", 1111, { matchNumber: 4 }),
      entry("b", "2027test_qm5", 2222, { matchNumber: "5" }),
    ]);
    expect(flags.get("a")?.[0]).toMatchObject({
      kind: "match",
      reason: "Scouted as match 4, but saved against Q5.",
    });
    expect(flags.has("b")).toBe(false);
  });

  it("checks a typed number with no key against the schedule only when there is one", () => {
    const rows = [entry("a", null, 1111, { matchNumber: 99 })];
    expect(detectFlags(rows).size).toBe(0);
    expect(detectFlags(rows, [1, 2, 3]).get("a")?.[0]).toMatchObject({
      kind: "match",
      reason: "Match 99 is not in the loaded schedule.",
    });
    expect(detectFlags(rows, [99]).size).toBe(0);
  });

  it("lists the worst flag first", () => {
    const flags = detectFlags(
      [
        entry("a", "2027test_qm1", 1111, { matchNumber: 2 }),
        entry("b", "2027test_qm1", 1111),
      ],
      [1],
    );
    expect(flags.get("a")?.map((f) => f.kind)).toEqual(["team", "match"]);
  });
});
