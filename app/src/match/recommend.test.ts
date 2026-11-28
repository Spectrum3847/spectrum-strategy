import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { computeStats, entryMatchKey, phaseStats } from "../team/stats";
import {
  climbOptions,
  noClimb,
  optionsFor,
  overrideOf,
  type Profile,
  profileOf,
  recommendClimb,
  recommendJobs,
  recommendPlans,
  recommendStarts,
  resolve,
  rolesLine,
  season,
  startOptions,
  withOverride,
} from "./recommend";

const config = parseConfig(bundled);

const withClimbTime = parseConfig({
  ...bundled,
  sections: bundled.sections.map((s) =>
    s.name === "Endgame"
      ? {
          ...s,
          fields: [
            ...s.fields,
            { title: "Time to climb (s)", type: "number", code: "climbSecs" },
          ],
        }
      : s,
  ),
});

const entry = (
  team: number,
  match: number,
  values: Record<string, unknown>,
): EventEntry => ({
  id: `${team}-${match}`,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: `2027test_qm${match}`,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

const matches = (team: number, rows: Record<string, unknown>[]) =>
  rows.map((values, i) => entry(team, i + 1, values));

function profile(team: number, entries: EventEntry[], cfg = config): Profile {
  const inputs = entries.map((e) => ({
    id: e.id,
    matchKey: entryMatchKey(e),
    fieldValues: e.fieldValues,
  }));
  return profileOf({
    config: cfg,
    team,
    entries,
    inputs,
    stats: computeStats(cfg, inputs),
    teleop: phaseStats(cfg, inputs).teleop,
  });
}

const repeat = (n: number, values: Record<string, unknown>) =>
  Array.from({ length: n }, () => values);

describe("options", () => {
  it("reads start spots and climb levels from the form", () => {
    expect(startOptions(config)).toEqual([
      "Depot Trench",
      "Outpost Trench",
      "Depot Bump",
      "Outpost Bump",
      "Center Hub",
    ]);
    expect(climbOptions(config)).toEqual([noClimb, "L1", "L2", "L3"]);
    expect(optionsFor(config, "job")).toEqual([
      "Score",
      "Feed",
      "Defend",
      "Flex",
    ]);
  });

  it("has no start or climb options on a form without them", () => {
    const bare = parseConfig({ ...bundled, sections: [] });
    expect(startOptions(bare)).toEqual([]);
    expect(climbOptions(bare)).toEqual([]);
    expect(recommendClimb(profile(1, [], bare))).toBeNull();
  });
});

describe("recommendJobs", () => {
  const scorer = profile(
    1,
    matches(1, repeat(4, { teleopFuelScored: 40, autoFuelScored: 10 })),
  );
  const close = profile(
    2,
    matches(2, repeat(4, { teleopFuelScored: 35, autoFuelScored: 10 })),
  );
  const defender = profile(
    3,
    matches(
      3,
      repeat(4, { teleopFuelScored: 10, autoFuelScored: 2, tRdefense: true }),
    ),
  );
  const feeder = profile(
    4,
    matches(
      4,
      repeat(4, { teleopFuelScored: 15, autoFuelScored: 5, tRpasser: true }),
    ),
  );
  const quiet = profile(
    5,
    matches(5, repeat(4, { teleopFuelScored: 15, autoFuelScored: 5 })),
  );
  const unscouted = profile(6, []);

  it("gives the best scorer Score and a close one Score", () => {
    const out = recommendJobs([scorer, close]);
    expect(out.get(1)?.value).toBe("Score");
    expect(out.get(1)?.why).toContain("best scorer");
    expect(out.get(2)?.value).toBe("Score");
    expect(out.get(2)?.why).toContain("scores close to 1");
  });

  it("gives a low scorer who defended often Defend, with the counts", () => {
    const out = recommendJobs([scorer, defender]);
    expect(out.get(3)?.value).toBe("Defend");
    expect(out.get(3)?.why).toContain("played defense 4 of 4 matches");
  });

  it("gives a low scorer who passed often Feed", () => {
    expect(recommendJobs([scorer, feeder]).get(4)?.value).toBe("Feed");
  });

  it("falls back to Flex with no strong role, or no scouting", () => {
    const out = recommendJobs([scorer, quiet, unscouted]);
    expect(out.get(5)?.value).toBe("Flex");
    expect(out.get(6)).toEqual({ value: "Flex", why: "not scouted yet" });
  });

  it("does not call a role from a single match", () => {
    const once = profile(
      7,
      matches(7, [
        { teleopFuelScored: 10, autoFuelScored: 2, tRdefense: true },
      ]),
    );
    expect(recommendJobs([scorer, once]).get(7)?.value).toBe("Flex");
  });

  it("makes nobody the scorer when no one has scored", () => {
    const zero = profile(8, matches(8, repeat(3, { teleopFuelScored: 0 })));
    const out = recommendJobs([zero]);
    expect(out.get(8)?.value).toBe("Flex");
  });
});

describe("recommendStarts", () => {
  const options = startOptions(config);
  const at = (team: number, spots: string[], fuel: number) =>
    profile(
      team,
      matches(
        team,
        spots.map((starting) => ({ starting, teleopFuelScored: fuel })),
      ),
    );

  it("keeps each robot's usual spot when partners differ", () => {
    const out = recommendStarts(
      [
        at(1, ["Depot Bump", "Depot Bump"], 30),
        at(2, ["Outpost Bump", "Outpost Bump"], 20),
      ],
      options,
    );
    expect(out.get(1)?.value).toBe("Depot Bump");
    expect(out.get(1)?.why).toBe("usual spot, 2 of 2 matches");
    expect(out.get(2)?.value).toBe("Outpost Bump");
  });

  it("gives a shared spot to the better scorer and moves the other", () => {
    const out = recommendStarts(
      [
        at(1, ["Depot Bump", "Depot Bump", "Center Hub"], 20),
        at(2, ["Depot Bump", "Depot Bump", "Depot Trench"], 40),
      ],
      options,
    );
    expect(out.get(2)?.value).toBe("Depot Bump");
    expect(out.get(1)?.value).not.toBe("Depot Bump");
    expect(out.get(1)?.why).toContain("Depot Bump goes to 2");
  });

  it("never puts two robots on one spot and gives unknowns a free one", () => {
    const out = recommendStarts(
      [
        at(1, ["Depot Bump"], 10),
        at(2, ["Depot Bump"], 20),
        at(3, ["Depot Bump"], 30),
        profile(4, []),
      ],
      options,
    );
    const spots = [...out.values()].map((c) => c.value);
    expect(new Set(spots).size).toBe(4);
    expect(out.get(4)?.why).toBe("no start data, so a free spot");
    expect(out.get(3)?.value).toBe("Depot Bump");
  });

  it("ignores no show answers", () => {
    const p = at(1, ["No Show", "No Show"], 10);
    expect(p.starts.size).toBe(0);
  });

  describe("auto by start spot", () => {
    const autos = (team: number, rows: [string, number][]) =>
      profile(
        team,
        matches(
          team,
          rows.map(([starting, autoFuelScored]) => ({
            starting,
            autoFuelScored,
          })),
        ),
      );

    it("says the spot can move when auto is the same from other spots", () => {
      const out = recommendStarts(
        [
          autos(1, [
            ["Depot Bump", 12],
            ["Depot Bump", 10],
            ["Center Hub", 11],
            ["Center Hub", 11],
          ]),
        ],
        options,
      );
      expect(out.get(1)?.why).toContain(
        "Auto is about the same from other spots (11 vs 11), so the spot can move",
      );
    });

    it("says when auto is better elsewhere", () => {
      const out = recommendStarts(
        [
          autos(1, [
            ["Depot Bump", 4],
            ["Depot Bump", 6],
            ["Depot Bump", 5],
            ["Center Hub", 20],
            ["Center Hub", 22],
          ]),
        ],
        options,
      );
      expect(out.get(1)?.why).toContain(
        "Auto is better elsewhere (21 vs 5 here)",
      );
    });

    it("says when auto is better at the chosen spot", () => {
      const out = recommendStarts(
        [
          autos(1, [
            ["Depot Bump", 20],
            ["Depot Bump", 22],
            ["Depot Bump", 21],
            ["Center Hub", 4],
            ["Center Hub", 6],
          ]),
        ],
        options,
      );
      expect(out.get(1)?.why).toContain(
        "Auto is better here (21 vs 5 elsewhere)",
      );
    });

    it("says nothing without two autos at the spot and two elsewhere", () => {
      const out = recommendStarts(
        [
          autos(1, [
            ["Depot Bump", 12],
            ["Depot Bump", 10],
            ["Center Hub", 30],
          ]),
        ],
        options,
      );
      expect(out.get(1)?.why).toBe("usual spot, 2 of 3 matches");
    });
  });
});

describe("recommendClimb", () => {
  const climbing = (
    team: number,
    results: ("Successful" | "Failed" | "N/A")[],
    teleop: number,
    level = "eHigh",
    cfg = config,
    extra: Record<string, unknown> = {},
  ) =>
    profile(
      team,
      matches(
        team,
        results.map((r) => ({
          [level]: r,
          teleopFuelScored: teleop,
          ...extra,
        })),
      ),
      cfg,
    );
  const seven: ("Successful" | "Failed")[] = [
    ...Array<"Successful">(7).fill("Successful"),
    "Failed",
  ];

  it("says no climb for a robot never scouted", () => {
    expect(recommendClimb(profile(1, []))).toEqual({
      value: noClimb,
      why: "not scouted yet",
    });
  });

  it("says no climb for a robot that never tried", () => {
    const out = recommendClimb(climbing(1, ["N/A", "N/A", "N/A"], 50));
    expect(out?.value).toBe(noClimb);
    expect(out?.why).toBe("never tried to climb in 3 scouted matches");
  });

  it("says no climb for a robot that failed every try", () => {
    const out = recommendClimb(climbing(1, ["Failed", "Failed"], 50));
    expect(out?.why).toBe("failed every climb, 0 of 2 tries");
  });

  it("does not trust a single try", () => {
    const out = recommendClimb(climbing(1, ["Successful"], 50));
    expect(out?.value).toBe(noClimb);
    expect(out?.why).toContain("only 1 try at L3");
  });

  it("says no climb below a half success rate", () => {
    const out = recommendClimb(
      climbing(1, ["Successful", "Failed", "Failed"], 50),
    );
    expect(out?.value).toBe(noClimb);
    expect(out?.why).toContain("only 1 of 3 tries");
  });

  it("climbs when the points beat the fuel lost, with the assumed time", () => {
    const out = recommendClimb(climbing(1, seven, season.teleopSeconds));
    expect(out?.value).toBe("L3");
    expect(out?.why).toContain("L3 made 7 of 8, worth about 26 points");
    expect(out?.why).toContain(`${season.assumedClimbSeconds}s (assumed)`);
    expect(out?.why).toContain("costs about 15 points of fuel, so climb");
  });

  it("keeps scoring when the fuel lost is worth more", () => {
    const out = recommendClimb(climbing(1, seven, season.teleopSeconds * 3));
    expect(out?.value).toBe(noClimb);
    expect(out?.why).toContain("so keep scoring");
  });

  it("rates the level they usually make at that level's own rate", () => {
    const mixed = profile(
      1,
      matches(1, [
        { eHigh: "Failed", teleopFuelScored: 20 },
        { eHigh: "Failed", teleopFuelScored: 20 },
        { eMiddle: "Successful", teleopFuelScored: 20 },
        { eMiddle: "Successful", teleopFuelScored: 20 },
      ]),
    );
    const out = recommendClimb(mixed);
    expect(out?.value).toBe("L2");
    expect(out?.why).toContain("L2 made 2 of 2");
  });

  it("uses the median recorded climb time and drops the assumed note", () => {
    const out = recommendClimb(
      climbing(1, seven, season.teleopSeconds / 2, "eHigh", withClimbTime, {
        climbSecs: 30,
      }),
    );
    expect(out?.why).toContain("takes about 30s and");
    expect(out?.why).not.toContain("(assumed)");
    expect(out?.why).toContain("costs about 15 points of fuel, so climb");
  });
});

describe("recommendPlans", () => {
  it("plans each alliance on its own", () => {
    const red = [
      profile(
        1,
        matches(1, repeat(3, { starting: "Depot Bump", teleopFuelScored: 30 })),
      ),
      profile(
        2,
        matches(2, repeat(3, { starting: "Depot Bump", teleopFuelScored: 20 })),
      ),
    ];
    const blue = [
      profile(
        3,
        matches(3, repeat(3, { starting: "Depot Bump", teleopFuelScored: 10 })),
      ),
    ];
    const plans = recommendPlans(config, [red, blue]);
    expect(plans.get(1)?.start?.value).toBe("Depot Bump");
    expect(plans.get(2)?.start?.value).not.toBe("Depot Bump");
    expect(plans.get(3)?.start?.value).toBe("Depot Bump");
    expect(plans.get(3)?.job.value).toBe("Score");
    expect(plans.get(3)?.climb?.value).toBe(noClimb);
  });
});

describe("roles", () => {
  it("lists the roles scouts marked out of the matches they answered", () => {
    const p = profile(
      1,
      matches(1, [
        { teleopFuelScored: 5, tRdefense: true },
        { teleopFuelScored: 5, tRdefense: false },
        { teleopFuelScored: 5, tRdefense: false, tRpasser: true },
      ]),
    );
    expect(rolesLine(p)).toBe("Defense 1/3, Passer/Pusher 1/1");
  });

  it("is empty when no role was marked", () => {
    expect(rolesLine(profile(1, matches(1, [{ teleopFuelScored: 5 }])))).toBe(
      "",
    );
  });
});

describe("overrides", () => {
  const rec = { value: "Score", why: "best scorer" };

  it("reads only answers that are one of today's options", () => {
    expect(overrideOf(config, "job", "defend")).toBe("Defend");
    expect(overrideOf(config, "job", "Hold the ramp")).toBeNull();
    expect(overrideOf(config, "start", " center hub ")).toBe("Center Hub");
    expect(overrideOf(config, "start", "Left")).toBeNull();
    expect(overrideOf(config, "climb", "L2")).toBe("L2");
    expect(overrideOf(config, "climb", undefined)).toBeNull();
  });

  it("shows the recommendation until the lead changes it", () => {
    expect(resolve(config, "job", rec, {})).toEqual({
      value: "Score",
      recommended: rec,
      changed: false,
    });
    expect(resolve(config, "job", rec, { teleop: "Defend" })).toEqual({
      value: "Defend",
      recommended: rec,
      changed: true,
    });
  });

  it("ignores old typed text and an override equal to the recommendation", () => {
    expect(
      resolve(config, "job", rec, { teleop: "Hold the ramp" }).changed,
    ).toBe(false);
    expect(resolve(config, "job", rec, { teleop: "Score" }).changed).toBe(
      false,
    );
  });

  it("stores the job in teleop, the start in start and the climb in endgame", () => {
    let roles = withOverride(config, {}, "job", "Feed");
    roles = withOverride(config, roles, "start", "Center Hub");
    roles = withOverride(config, roles, "climb", noClimb);
    expect(roles).toEqual({
      teleop: "Feed",
      start: "Center Hub",
      endgame: noClimb,
    });
  });

  it("clears an override and keeps text that was never one", () => {
    const roles = { auto: "Two fuel", start: "Left", teleop: "Feed" };
    expect(withOverride(config, roles, "job", null)).toEqual({
      auto: "Two fuel",
      start: "Left",
    });
    expect(withOverride(config, roles, "start", null)).toBe(roles);
  });
});
