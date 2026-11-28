import { describe, expect, it } from "vitest";
import pitDefault from "../../../assets/pit_scout_config_default.json";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry, PitEntry } from "../data/parse";
import { incidentsByTeam } from "../picks/incidents";
import { parseConfig } from "../scout/config";
import { emptyRow, type TeamRow } from "../teams/rows";
import {
  cardColors,
  cardedTeams,
  panelFacts,
  rankedTeams,
  tankTeams,
} from "./derive";

const config = parseConfig(bundled);
const pitConfig = parseConfig(pitDefault);

const row = (team: number, total: number | null, matches = 3): TeamRow => ({
  ...emptyRow(team),
  listed: true,
  matches,
  mean: { total, auto: null, teleop: null },
});

let n = 0;
const entry = (
  team: number,
  match: number,
  values: Record<string, unknown>,
): EventEntry => ({
  id: `e${n++}`,
  tbaMatchKey: `2027test_qm${match}`,
  teamNumber: team,
  alliance: "Red",
  scoutName: "Scout A",
  updatedAt: "2027-03-01T12:00:00.000Z",
  fieldValues: values,
});

const pitEntry = (
  team: number,
  updatedAt: string,
  values: Record<string, unknown>,
): PitEntry => ({
  id: `p${n++}`,
  teamNumber: team,
  eventKey: "2027test",
  authorUid: "u1",
  scoutName: "Scout A",
  updatedAt,
  fieldValues: values,
  photoKeys: [],
});

describe("rankedTeams", () => {
  it("orders scouted teams by average total and leaves out unscouted ones", () => {
    const out = rankedTeams([
      row(3333, 10),
      row(1111, 30),
      row(2222, 30),
      row(4444, null),
      row(5555, 99, 0),
    ]);
    expect(out.map((r) => r.team)).toEqual([1111, 2222, 3333, 4444]);
  });
});

describe("cards", () => {
  it("keeps the most severe card per team", () => {
    const colors = cardColors(
      incidentsByTeam([
        entry(1111, 1, { ryCard: "Yellow" }),
        entry(1111, 2, { ryCard: "Red" }),
        entry(2222, 1, { ryCard: "Yellow" }),
        entry(3333, 1, { ryCard: true }),
        entry(4444, 1, { ryCard: "None" }),
      ]),
    );
    expect(colors.get(1111)).toBe("red");
    expect(colors.get(2222)).toBe("yellow");
    expect(colors.get(3333)).toBe("unknown");
    expect(colors.has(4444)).toBe(false);
    expect(cardedTeams(colors)).toEqual([1111, 2222, 3333]);
  });
});

describe("tankTeams", () => {
  it("lists teams whose newest pit answer names a tank drive", () => {
    const old = "2027-03-01T10:00:00.000Z";
    const recent = "2027-03-01T12:00:00.000Z";
    const out = tankTeams(
      [
        pitEntry(2222, old, { drivetrainType: "tank" }),
        pitEntry(2222, recent, { drivetrainType: "swerve" }),
        pitEntry(1111, recent, { drivetrainType: "Tank drive" }),
        pitEntry(3333, recent, {}),
      ],
      pitConfig,
    );
    expect(out).toEqual([1111]);
  });
});

describe("panelFacts", () => {
  it("averages fuel, reads the pit answers and keeps comments", () => {
    const facts = panelFacts(1111, {
      config,
      pitConfig,
      entries: [
        entry(1111, 1, { autoFuelScored: 2, teleopFuelScored: 10 }),
        entry(1111, 2, { autoFuelScored: 4, teleopFuelScored: 20 }),
        entry(2222, 1, { autoFuelScored: 9, teleopFuelScored: 9 }),
      ],
      pit: [
        pitEntry(1111, "2027-03-01T12:00:00.000Z", {
          driveCoachName: "Coach A",
        }),
      ],
    });
    expect(facts.matches).toBe(2);
    expect(facts.avgAuto).toBe(3);
    expect(facts.avgTeleop).toBe(15);
    expect(facts.driveCoach).toBe("Coach A");
  });

  it("reports nothing for a team with no entries", () => {
    const facts = panelFacts(9999, { config, pitConfig, entries: [], pit: [] });
    expect(facts.matches).toBe(0);
    expect(facts.avgAuto).toBeNull();
    expect(facts.robotType).toBe("");
    expect(facts.comments).toEqual([]);
  });
});
