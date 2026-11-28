import { describe, expect, it } from "vitest";
import {
  knownRefs,
  nextMatchNumberFor,
  resolveMatchKey,
  type ScheduledMatch,
  stationOf,
  teamForStation,
} from "./schedule";
import { parseMatches } from "./tba";

const match = (n: number, level = "qm"): ScheduledMatch => ({
  key: `2027test_${level}${n}`,
  compLevel: level,
  matchNumber: n,
  red: [100 + n, 200 + n, 300 + n],
  blue: [400 + n, 500 + n, 600 + n],
});
const schedule = [match(1), match(2), match(3), match(1, "sf")];

describe("teamForStation", () => {
  it("finds the team in a qualification slot", () => {
    expect(teamForStation(schedule, 2, "R1")).toBe(102);
    expect(teamForStation(schedule, 2, "B3")).toBe(602);
    expect(teamForStation(schedule, 2, "Red 2")).toBe(202);
  });

  it("is null without a match, a station or a schedule entry", () => {
    expect(teamForStation(schedule, null, "R1")).toBeNull();
    expect(teamForStation(schedule, 2, "nope")).toBeNull();
    expect(teamForStation(schedule, 9, "R1")).toBeNull();
  });
});

describe("nextMatchNumberFor", () => {
  it("starts at the first qualification match with nothing saved", () => {
    expect(nextMatchNumberFor("R1", schedule, [])).toBe(1);
  });

  it("is null with no qualification schedule or no station", () => {
    expect(nextMatchNumberFor("R1", [match(1, "sf")], [])).toBeNull();
    expect(nextMatchNumberFor("", schedule, [])).toBeNull();
  });

  it("moves past matches this station already saved", () => {
    const saved = [
      { tbaMatchKey: "2027test_qm1", station: "R1" },
      { tbaMatchKey: "2027test_qm2", station: "R1" },
    ];
    expect(nextMatchNumberFor("R1", schedule, saved)).toBe(3);
  });

  it("does not skip for another station's saves unless two agree", () => {
    const one = [{ tbaMatchKey: "2027test_qm2", station: "B1" }];
    expect(nextMatchNumberFor("R1", schedule, one)).toBe(1);
    const two = [...one, { tbaMatchKey: "2027test_qm2", station: "B2" }];
    expect(nextMatchNumberFor("R1", schedule, two)).toBe(2);
  });

  it("is null once every match is saved", () => {
    const saved = [1, 2, 3].map((n) => ({
      tbaMatchKey: `2027test_qm${n}`,
      station: "R1",
    }));
    expect(nextMatchNumberFor("R1", schedule, saved)).toBeNull();
  });

  it("ignores entries with no key or an unreadable station", () => {
    const saved = [
      { tbaMatchKey: null, station: "R1" },
      { tbaMatchKey: "2027test_qm1", station: "" },
    ];
    expect(nextMatchNumberFor("R1", schedule, saved)).toBe(1);
  });
});

describe("next match across scouts", () => {
  const remote = (id: string, n: number, robot: string) => ({
    id,
    tbaMatchKey: `2027test_qm${n}`,
    fieldValues: { robot },
  });

  it("counts other scouts: two stations on match 2 start a new station at 2", () => {
    const others = [remote("a", 2, "B1"), remote("b", 2, "B2")];
    expect(nextMatchNumberFor("R1", schedule, knownRefs([], others))).toBe(2);
    expect(nextMatchNumberFor("R1", schedule, [])).toBe(1);
  });

  it("skips what this station has synced from another device", () => {
    const others = [remote("a", 1, "R1"), remote("b", 2, "R1")];
    expect(nextMatchNumberFor("R1", schedule, knownRefs([], others))).toBe(3);
  });

  it("counts an entry once when saved here and echoed back", () => {
    const here = [{ id: "a", tbaMatchKey: "2027test_qm1", station: "R1" }];
    expect(knownRefs(here, [remote("a", 1, "R1")])).toHaveLength(1);
  });

  it("keeps entries saved here that the database has not returned yet", () => {
    const here = [{ id: "new", tbaMatchKey: "2027test_qm1", station: "R1" }];
    expect(nextMatchNumberFor("R1", schedule, knownRefs(here, []))).toBe(2);
  });

  it("reads the station from a team-and-robot value, and ignores typed matches", () => {
    const refs = knownRefs(
      [],
      [
        {
          id: "x",
          tbaMatchKey: "2027test_qm1",
          fieldValues: { pick: { teamNumber: 1, robotPosition: "R1" } },
        },
        { id: "y", tbaMatchKey: null, fieldValues: { robot: "R1" } },
      ],
    );
    expect(refs).toEqual([
      { tbaMatchKey: "2027test_qm1", station: "R1" },
      { tbaMatchKey: null, station: "R1" },
    ]);
    expect(nextMatchNumberFor("R1", schedule, refs)).toBe(2);
  });
});

describe("helpers", () => {
  it("reads the station from robot or a team-and-robot value", () => {
    expect(stationOf({ robot: "B2" })).toBe("B2");
    expect(stationOf({ pick: { teamNumber: 5, robotPosition: "R3" } })).toBe(
      "R3",
    );
    expect(stationOf({})).toBe("");
  });

  it("resolves typed match text to a key", () => {
    expect(resolveMatchKey("2", schedule)).toBe("2027test_qm2");
    expect(resolveMatchKey("Q3", schedule)).toBe("2027test_qm3");
    expect(resolveMatchKey("qm1", schedule)).toBe("2027test_qm1");
    expect(resolveMatchKey("9", schedule)).toBeNull();
    expect(resolveMatchKey("sf1", schedule)).toBeNull();
  });
});

describe("parseMatches", () => {
  it("reads TBA matches and sorts by level then number", () => {
    const parsed = parseMatches([
      {
        key: "2027test_qm2",
        comp_level: "qm",
        match_number: 2,
        alliances: {
          red: { team_keys: ["frc11", "frc12", "frc13"] },
          blue: { team_keys: ["frc21", "frc22", "frc23"] },
        },
      },
      {
        key: "2027test_qm1",
        comp_level: "qm",
        match_number: 1,
        alliances: { red: { team_keys: [] }, blue: { team_keys: [] } },
      },
      { nonsense: true },
    ]);
    expect(parsed.map((m) => m.matchNumber)).toEqual([1, 2]);
    expect(parsed[1]?.red).toEqual([11, 12, 13]);
    expect(parsed[1]?.blue).toEqual([21, 22, 23]);
  });

  it("returns nothing for a non-list answer", () => {
    expect(parseMatches({ error: "bad" })).toEqual([]);
  });
});
