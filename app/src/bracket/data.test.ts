import { expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { parseEventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { report, robotsFor, scenarios } from "./data";

it("scores scouting once per match and reports start clashes", () => {
  const entry = (id: string, team: number, match: number, fuel: number) =>
    parseEventEntry(id, {
      teamNumber: team,
      tbaMatchKey: `event_qm${match}`,
      fieldValues: {
        autoFuelScored: fuel,
        teleopFuelScored: 20,
        auLow: "Successful",
        eHigh: "Successful",
        starting: "Depot Bump",
      },
    });
  const robots = robotsFor(parseConfig(bundled), [
    entry("a", 1111, 1, 5),
    entry("b", 1111, 1, 15),
    entry("c", 2222, 1, 10),
  ]);
  expect(robots.get(1111)?.score).toBe(75);
  expect(robots.get(1111)?.n).toBe(1);
  expect(report([1111, 2222], robots).clashes).toEqual(["Depot Bump"]);
});
it("expects the plain average of every match, not the middle half", () => {
  const entry = (match: number, auto: number) =>
    parseEventEntry(`e${match}`, {
      teamNumber: 1111,
      tbaMatchKey: `event_qm${match}`,
      fieldValues: { autoFuelScored: auto, teleopFuelScored: 20 },
    });
  const robots = robotsFor(parseConfig(bundled), [
    entry(1, 10),
    entry(2, 10),
    entry(3, 10),
    entry(4, 50),
  ]);
  expect(robots.get(1111)?.score).toBe(40);
  expect(robots.get(1111)?.auto).toBe(20);
});
it("drafts six deterministic scenarios with unique teams", () => {
  const ranking = Array.from({ length: 32 }, (_, i) => 1001 + i);
  const robots = new Map(
    ranking.map((t, i) => [
      t,
      {
        score: 100 - i,
        sigma: 10,
        n: 1,
        auto: 10,
        teleop: 50,
        climb: 10,
        driver: null,
        start: "",
        incidents: "",
      },
    ]),
  );
  const result = scenarios(ranking, 2, 1001, null, robots);
  expect(result).toHaveLength(6);
  expect(result).toEqual(scenarios(ranking, 2, 1001, null, robots));
  for (const scenario of result)
    expect(new Set(scenario.alliances.flat()).size).toBe(24);
});
