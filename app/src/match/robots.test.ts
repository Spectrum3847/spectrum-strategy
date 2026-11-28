import { describe, expect, it } from "vitest";
import bundledPit from "../../../assets/pit_scout_config_default.json";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry, PitEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import {
  buildRobots,
  climbLabel,
  epaTotal,
  factsFor,
  robotType,
  scoutedInMatch,
  scoutedTotal,
} from "./robots";

const config = parseConfig(bundled);
const pitConfig = parseConfig(bundledPit);

const entry = (
  id: string,
  team: number,
  key: string,
  values: Record<string, unknown>,
  updatedAt = "2027-03-01T10:00:00.000Z",
): EventEntry => ({
  id,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: "Scout A",
  updatedAt,
  fieldValues: values,
});

const pitEntry = (team: number, values: Record<string, unknown>): PitEntry => ({
  id: `pit${team}`,
  teamNumber: team,
  eventKey: "2027test",
  fieldValues: values,
  scoutName: "Scout B",
  updatedAt: "2027-03-01T09:00:00.000Z",
  authorUid: "uid-b",
  photoKeys: [],
});

const entries = [
  entry("a", 1111, "2027test_qm1", {
    autoFuelScored: 4,
    teleopFuelScored: 10,
    eMiddle: "Successful",
    comments: "Fast intake",
  }),
  entry(
    "b",
    1111,
    "2027test_qm2",
    {
      autoFuelScored: 6,
      teleopFuelScored: 20,
      eLow: "Successful",
      comments: "Died late",
    },
    "2027-03-01T11:00:00.000Z",
  ),
  entry("c", 4444, "2027test_qm1", { autoFuelScored: 2, teleopFuelScored: 5 }),
];

const base = {
  config,
  pitConfig,
  matchKey: "2027test_qm3",
  red: [1111, 2222, 3333],
  blue: [4444, 5555, 6666],
  entries,
  pit: [] as PitEntry[],
  nicknames: new Map([[1111, "Alpha Bots"]]),
  epa: null,
};

describe("buildRobots", () => {
  const rows = buildRobots(base);

  it("lists red then blue, one row per robot", () => {
    expect(rows.map((r) => [r.team, r.side])).toEqual([
      [1111, "red"],
      [2222, "red"],
      [3333, "red"],
      [4444, "blue"],
      [5555, "blue"],
      [6666, "blue"],
    ]);
    expect(rows[0]?.nickname).toBe("Alpha Bots");
  });

  it("takes the typical auto and teleop from this team's entries", () => {
    const first = rows[0];
    expect(first?.matches).toBe(2);
    expect(first?.auto).toBeCloseTo(5);
    expect(first?.teleop).toBeCloseTo(15);
  });

  it("leaves an unscouted robot empty", () => {
    const second = rows[1];
    expect(second?.matches).toBe(0);
    expect(second?.auto).toBeNull();
    expect(second?.teleop).toBeNull();
    expect(second?.climb).toBe("");
    expect(second?.comment).toBeNull();
  });

  it("reads the best climb seen and the newest comment", () => {
    expect(rows[0]?.climb).toBe("L2");
    expect(rows[0]?.comment?.text).toBe("Died late");
  });

  it("finds the total scouted in this very match", () => {
    const row = buildRobots({ ...base, matchKey: "2027test_QM1" })[0];
    expect(row?.thisMatch).toBe(14);
    expect(rows[0]?.thisMatch).toBeNull();
  });

  it("reads max and IQM fuel per scout entry, and a successful auto climb", () => {
    const first = buildRobots({
      ...base,
      entries: [
        ...entries,
        entry("d", 1111, "2027test_qm3", { auLow: "Successful" }),
      ],
    })[0];
    expect(first?.maxAuto).toBe(6);
    expect(first?.maxTeleop).toBe(20);
    expect(first?.iqmFuel).toBeCloseTo(15);
    expect(first?.autoClimb).toBe(true);
    expect(rows[0]?.autoClimb).toBe(false);
    expect(rows[1]?.maxAuto).toBeNull();
    expect(rows[1]?.iqmFuel).toBeNull();
  });

  it("does not count another team's entries", () => {
    expect(rows[3]?.matches).toBe(1);
    expect(rows[3]?.auto).toBe(2);
  });
});

describe("predictions", () => {
  it("sums EPA and says nothing when no robot has any", () => {
    const rows = buildRobots({ ...base, epa: { 1111: 20, 2222: 10, 4444: 5 } });
    expect(epaTotal(rows, "red")).toBe(30);
    expect(epaTotal(rows, "blue")).toBe(5);
    expect(epaTotal(buildRobots(base), "red")).toBeNull();
    expect(epaTotal(buildRobots({ ...base, epa: {} }), "blue")).toBeNull();
  });

  it("sums typical auto and teleop, counting an unscouted robot as 0", () => {
    const rows = buildRobots(base);
    expect(scoutedTotal(rows, "red")).toBeCloseTo(20);
    expect(scoutedTotal(rows, "blue")).toBeCloseTo(7);
  });

  it("makes no scouted prediction until a robot is scouted", () => {
    const rows = buildRobots({ ...base, entries: [] });
    expect(scoutedTotal(rows, "red")).toBeNull();
  });

  it("totals what the scouts recorded in a played match", () => {
    const rows = buildRobots({ ...base, matchKey: "2027test_qm1" });
    expect(scoutedInMatch(rows, "red")).toEqual({
      total: 14,
      robots: 1,
      of: 3,
    });
    expect(scoutedInMatch(rows, "blue")).toEqual({
      total: 7,
      robots: 1,
      of: 3,
    });
  });
});

describe("robotType", () => {
  it("joins drive train, trench fit and launcher", () => {
    const field = pitConfig.sections
      .flatMap((s) => s.fields)
      .find((f) => f.code === "drivetrainType");
    const key = field?.choices?.[0]?.[0] ?? "";
    const label = field?.choices?.[0]?.[1] ?? "";
    const entry = pitEntry(1111, {
      drivetrainType: key,
      trenchFit: true,
      launcherType: " Twin flywheel ",
    });
    expect(robotType(entry, pitConfig)).toBe(
      `${label} · trench · Twin flywheel`,
    );
  });

  it("drops unanswered parts and says bump for a false fit", () => {
    expect(robotType(pitEntry(1, { trenchFit: false }), pitConfig)).toBe(
      "bump",
    );
    expect(robotType(pitEntry(1, {}), pitConfig)).toBe("");
    expect(robotType(null, pitConfig)).toBe("");
  });

  it("reaches the table through the newest pit entry", () => {
    const rows = buildRobots({
      ...base,
      pit: [pitEntry(1111, { launcherType: "Hood" })],
    });
    expect(rows[0]?.robotType).toBe("Hood");
  });
});

describe("climbLabel", () => {
  const rate = (label: string, successes: number) => ({
    code: label,
    label,
    section: "Endgame",
    successes,
    total: 3,
  });

  it("is the highest level with a success", () => {
    expect(
      climbLabel([
        rate("Low Climb (L1)", 2),
        rate("Middle Climb (L2)", 1),
        rate("High Climb (L3)", 0),
      ]),
    ).toBe("L2");
  });

  it("is empty with no success or no climb field", () => {
    expect(climbLabel([rate("Low Climb (L1)", 0)])).toBe("");
    expect(climbLabel([rate("Defense", 3)])).toBe("");
  });
});

describe("factsFor", () => {
  it("states only what is known", () => {
    const rows = buildRobots({ ...base, epa: { 1111: 20 } });
    expect(factsFor(rows[0] as (typeof rows)[number])).toEqual([
      "EPA 20.0 points",
      "Scouted in 2 matches, typical score 20.0",
      "Typical auto 5.0, teleop 15.0",
      "Best endgame climb seen: L2",
    ]);
    expect(factsFor(rows[1] as (typeof rows)[number])).toEqual([
      "Not scouted yet",
    ]);
  });
});
