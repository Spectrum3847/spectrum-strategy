import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry, TrexReport } from "../data/parse";
import type { AllianceFuel } from "../data/tbaBreakdown";
import { parseConfig } from "../scout/config";
import { explainPrediction, explainResult } from "./explain";

const config = parseConfig(bundled);
const RED = [1111, 2222, 3333];
const BLUE = [4444, 5555, 6666];

const entry = (
  team: number,
  n: number,
  values: Record<string, unknown>,
): EventEntry => ({
  id: `${team}-${n}`,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: `2027test_qm${n}`,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

const earlier = [
  ...RED.flatMap((t) =>
    [1, 2, 3].map((n) =>
      entry(t, n, { autoFuelScored: 3 + n, teleopFuelScored: 9 + n }),
    ),
  ),
  ...BLUE.flatMap((t) =>
    [1, 2, 3].map((n) =>
      entry(t, n, { autoFuelScored: 1 + n, teleopFuelScored: 3 + n }),
    ),
  ),
];

describe("explainPrediction", () => {
  it("turns the gap into the win chance and names the drivers", () => {
    const why = explainPrediction({
      red: RED,
      blue: BLUE,
      entries: earlier,
      epa: { 1111: 30, 2222: 30, 3333: 30, 4444: 10, 5555: 10, 6666: 10 },
      tba: { redScore: 80, blueScore: 50, redWin: 0.8 },
    });
    expect(why.lines[0]).toMatch(
      /^Scouting expects Red to score 48 fuel to 24, 24 ahead\./,
    );
    expect(why.lines[0]).toContain("99% chance");
    expect(why.lines.some((l) => /scores the most/.test(l))).toBe(true);
    expect(why.lines.some((l) => /least predictable/.test(l))).toBe(true);
    expect(why.lines).toContain(
      "The Blue Alliance has Red at 80%. It agrees on the favourite.",
    );
    expect(why.lines).toContain("Statbotics expects Red 90 points to Blue 30.");
    expect(why.robots[0]).toMatchObject({
      team: 1111,
      side: "red",
      mean: 16,
      entries: 3,
      epa: 30,
    });
  });

  it("names the robots without enough scouting instead of guessing", () => {
    const why = explainPrediction({
      red: RED,
      blue: BLUE,
      entries: earlier.filter((e) => e.teamNumber !== 4444),
      epa: null,
      tba: { redScore: 0, blueScore: 0, redWin: 0.3 },
    });
    expect(why.lines[0]).toBe(
      "Scouting gives no win chance: 4444 has fewer than 3 scouted matches.",
    );
    expect(why.lines[1]).toBe("The Blue Alliance has Red at 30%.");
    expect(why.robots.find((r) => r.team === 4444)?.mean).toBeNull();
  });
});

describe("explainResult", () => {
  const own = [
    entry(1111, 4, {
      autoFuelScored: 6,
      teleopFuelScored: 14,
      comments: "Jammed twice",
      tRdefense: true,
    }),
    entry(2222, 4, { autoFuelScored: 5, teleopFuelScored: 11 }),
    entry(3333, 4, { autoFuelScored: 4, teleopFuelScored: 10, dieCard: true }),
    entry(4444, 4, { tRdefense: true, autoFuelScored: 2, teleopFuelScored: 5 }),
  ];
  const side = (
    alliance: "red" | "blue",
    extra: Partial<AllianceFuel>,
  ): AllianceFuel => ({
    matchKey: "2027test_qm4",
    alliance,
    teams: alliance === "red" ? RED : BLUE,
    count: 30,
    ...extra,
  });
  const base = {
    config,
    matchKey: "2027test_qm4",
    red: RED,
    blue: BLUE,
    redScore: 40,
    blueScore: 35,
    entries: [...earlier, ...own],
    redWin: 0.9,
    chanceFrom: "our scouting",
    tba: null,
    trex: [],
  };

  it("splits the fuel miss into robots against forecast and unseen fuel", () => {
    const why = explainResult({
      ...base,
      breakdown: [
        side("red", {
          count: 30,
          climbPoints: 6,
          foulPoints: 4,
          foulCount: 1,
          video: "abc123",
        }),
      ],
    });
    const red = why.sides.red;
    expect(red.split).toEqual({ miss: -18, robotPart: 2, unseen: -20 });
    expect(red.split?.robotPart).toBe(
      red.robots.reduce((s, r) => s + (r.delta ?? 0), 0),
    );
    expect(red.split?.miss).toBe(
      (red.split?.robotPart ?? 0) + (red.split?.unseen ?? 0),
    );
    expect(red).toMatchObject({ fuel: 30, climb: 6, fouls: 4, rest: 0 });
    expect(why.video).toBe("abc123");
  });

  it("measures each robot against forecasts from earlier matches only", () => {
    const why = explainResult({ ...base, breakdown: [] });
    const first = why.sides.red.robots[0];
    expect(first).toMatchObject({ team: 1111, forecast: 16, scouted: 20 });
    expect(first?.delta).toBe(4);
  });

  it("carries the scouts' flags and comment for a robot", () => {
    const why = explainResult({ ...base, breakdown: [] });
    const [a, , c] = why.sides.red.robots;
    expect(a?.notes).toContain("Defense");
    expect(a?.comment).toEqual({ text: "Jammed twice", scout: "Scout A" });
    expect(c?.notes).toContain("Broke down or did not show");
    expect(why.sides.blue.defenders).toEqual([1111]);
    expect(why.sides.red.defenders).toEqual([4444]);
  });

  it("does not split when a robot was not scouted or the count is missing", () => {
    expect(
      explainResult({ ...base, breakdown: [] }).sides.red.split,
    ).toBeNull();
    const why = explainResult({
      ...base,
      entries: [...earlier, ...own.filter((e) => e.teamNumber !== 3333)],
      breakdown: [side("red", {})],
    });
    expect(why.sides.red.split).toBeNull();
  });

  it("puts the largest reasons first and says upset or as predicted", () => {
    const why = explainResult({
      ...base,
      breakdown: [side("red", { count: 30 })],
    });
    expect(why.headline).toBe(
      "Red won by 5, as predicted (90% from our scouting).",
    );
    expect(why.causes[0]).toMatch(/^3333 \(red\)|^Red's official fuel was -20/);
    expect(why.causes.some((c) => /scouts marked: broke down/.test(c))).toBe(
      true,
    );
    const upset = explainResult({ ...base, redWin: 0.2, breakdown: [] });
    expect(upset.headline).toBe(
      "Red won by 5, an upset (our scouting had Blue at 80%).",
    );
  });

  it("lists T-REx notes written for this match", () => {
    const report = (n: number, text: string): TrexReport => ({
      id: `r${n}`,
      trait: "defense",
      teamNumber: 1111,
      matchNumber: n,
      eventName: "",
      eventKey: "2027test",
      report: text,
      rating: 4,
      scoutName: "Scout B",
      updatedAt: "2027-03-01T10:00:00.000Z",
    });
    const why = explainResult({
      ...base,
      breakdown: [],
      trex: [
        report(4, "Pinned a partner"),
        report(3, "Earlier"),
        report(4, ""),
      ],
    });
    expect(why.trex.map((t) => t.text)).toEqual(["Pinned a partner"]);
  });
});
