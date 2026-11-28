import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { parseConfig } from "../scout/config";
import {
  computeStats,
  groupByMatch,
  iqm,
  mean,
  phaseStats,
  type StatInput,
  sd,
} from "./stats";

const config = parseConfig(bundled);

function entry(
  id: string,
  matchKey: string,
  fieldValues: Record<string, unknown>,
): StatInput {
  return { id, matchKey, fieldValues };
}

const row = (stats: ReturnType<typeof computeStats>, code: string) =>
  stats.rows.find((r) => r.code === code);
const rate = (stats: ReturnType<typeof computeStats>, code: string) =>
  stats.rates.find((r) => r.code === code);

describe("iqm, mean and sd", () => {
  it("takes the mean of the middle half", () => {
    expect(iqm([1, 2, 3, 4, 5, 6, 7, 8])).toBe(4.5);
  });

  it("weights the boundary values when n is not a multiple of four", () => {
    expect(iqm([1, 2, 3, 4, 100])).toBe(3);
  });

  it("is the plain mean below four samples", () => {
    expect(iqm([2, 4, 9])).toBe(5);
    expect(iqm([])).toBe(0);
  });

  it("uses the population standard deviation", () => {
    expect(sd([2, 4, 4, 4, 5, 5, 7, 9])).toBe(2);
    expect(mean([1, 2, 3])).toBe(2);
  });
});

describe("computeStats", () => {
  const entries = [
    entry("a", "2027test_qm1", { autoFuelScored: 4, teleopFuelScored: 10 }),
    entry("b", "2027test_qm2", { autoFuelScored: 6, teleopFuelScored: 20 }),
    entry("c", "2027test_qm3", { autoFuelScored: 2, teleopFuelScored: 0 }),
  ];

  it("gives mean, iqm, max, sd and n per counter, from the config", () => {
    const stats = computeStats(config, entries);
    expect(row(stats, "autoFuelScored")).toMatchObject({
      label: "Fuel Scored",
      section: "Autonomous",
      n: 3,
      mean: 4,
      iqm: 4,
      max: 6,
    });
    expect(row(stats, "teleopFuelScored")?.max).toBe(20);
    expect(row(stats, "teleopFuelScored")?.sd).toBeCloseTo(8.165, 3);
  });

  it("counts several scouts on one team in one match as one match, averaged", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { teleopFuelScored: 10 }),
      entry("b", "2027test_qm1", { teleopFuelScored: 20 }),
      entry("c", "2027test_qm2", { teleopFuelScored: 30 }),
    ]);
    const teleop = row(stats, "teleopFuelScored");
    expect(stats.matches).toBe(2);
    expect(teleop?.n).toBe(2);
    expect(teleop?.mean).toBe(22.5);
    expect(teleop?.max).toBe(30);
  });

  it("leaves an entry without the key out instead of reading it as zero", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { teleopFuelScored: 10 }),
      entry("b", "2027test_qm2", {}),
    ]);
    expect(row(stats, "teleopFuelScored")?.n).toBe(1);
    expect(row(stats, "teleopFuelScored")?.sd).toBeNull();
  });

  it("totals the counters of the phase sections per match", () => {
    const stats = computeStats(config, entries);
    expect(stats.series).toEqual([
      { key: "2027test_qm1", value: 14 },
      { key: "2027test_qm2", value: 26 },
      { key: "2027test_qm3", value: 2 },
    ]);
    expect(stats.total).toMatchObject({ n: 3, max: 26 });
  });

  it("keeps a range such as accuracy out of the total but still shows it", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { teleopFuelScored: 10, scoringEff: 80 }),
    ]);
    expect(stats.series[0]?.value).toBe(10);
    expect(row(stats, "scoringEff")?.mean).toBe(80);
  });

  it("does not treat the team number as a metric", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { pTnumber: "1111", teleopFuelScored: 1 }),
    ]);
    expect(row(stats, "pTnumber")).toBeUndefined();
  });

  it("reads numeric text", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { teleopFuelScored: "12" }),
    ]);
    expect(row(stats, "teleopFuelScored")?.mean).toBe(12);
  });

  it("orders the series by play order, not arrival order", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_sf1m1", { teleopFuelScored: 1 }),
      entry("b", "2027test_qm10", { teleopFuelScored: 2 }),
      entry("c", "2027test_qm2", { teleopFuelScored: 3 }),
    ]);
    expect(stats.series.map((p) => p.key)).toEqual([
      "2027test_qm2",
      "2027test_qm10",
      "2027test_sf1m1",
    ]);
  });

  it("has no rows for a team with no entries", () => {
    const stats = computeStats(config, []);
    expect(stats).toMatchObject({
      matches: 0,
      total: null,
      rows: [],
      rates: [],
    });
  });
});

const generic = parseConfig({
  title: "T",
  revision: 1,
  sections: [
    {
      name: "Pre",
      fields: [
        {
          code: "st",
          title: "Start",
          type: "select",
          choices: { "0": "No Show", "1": "Left", "2": "Right" },
        },
      ],
    },
    {
      name: "Teleop",
      fields: [
        { code: "pieces", title: "Pieces", type: "counter" },
        { code: "q1", title: "Robot died", type: "boolean" },
        { code: "q2", title: "Lost comms and disconnected", type: "boolean" },
        { code: "q3", title: "Picked up a red card", type: "boolean" },
      ],
    },
  ],
});

const play = (n: number, extra: Record<string, unknown> = {}) => ({
  st: "1",
  pieces: n,
  ...extra,
});

function genericStats(rows: Record<string, unknown>[]) {
  return computeStats(
    generic,
    rows.map((values, i) => entry(`e${i}`, `2027test_qm${i + 1}`, values)),
  );
}

describe("breakdowns", () => {
  it("counts died and disconnected matches, by title", () => {
    const stats = genericStats([
      play(10),
      play(0, { q1: true }),
      play(12),
      play(0, { q2: true }),
    ]);
    expect(stats.reliability).toEqual({ ok: 2, of: 4 });
    expect(stats.total).toMatchObject({ n: 4, typical: 11, typicalN: 2 });
  });

  it("does not count a card as a breakdown", () => {
    const stats = genericStats([play(10, { q3: true }), play(12)]);
    expect(stats.reliability).toEqual({ ok: 2, of: 2 });
  });

  it("counts a No Show start position, unless the entry played", () => {
    const stats = genericStats([
      play(10),
      play(0, { st: "0" }),
      play(14, { st: "0" }),
    ]);
    expect(stats.reliability).toEqual({ ok: 2, of: 3 });
    expect(stats.total).toMatchObject({ n: 3, typical: 12 });
  });

  it("goes with the scouts of a match: most must say it", () => {
    const rows = [
      entry("a", "2027test_qm1", play(10, { q1: true })),
      entry("b", "2027test_qm1", play(10, { q1: false })),
      entry("c", "2027test_qm1", play(10, { q1: true })),
      entry("d", "2027test_qm2", play(10, { q1: true })),
      entry("e", "2027test_qm2", play(10, { q1: false })),
    ];
    expect(computeStats(generic, rows).reliability).toEqual({ ok: 1, of: 2 });
  });

  it("works on the bundled 2026 form", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { teleopFuelScored: 30 }),
      entry("b", "2027test_qm2", { teleopFuelScored: 0, dieCard: true }),
      entry("c", "2027test_qm3", { teleopFuelScored: 50 }),
    ]);
    expect(stats.reliability).toEqual({ ok: 2, of: 3 });
    expect(stats.total).toMatchObject({ mean: 80 / 3, typical: 40 });
  });

  it("leaves breakdowns out of the error and the floor too", () => {
    const stats = genericStats([
      play(10),
      play(20),
      play(30),
      play(40),
      play(0, { q1: true }),
    ]);
    expect(stats.total).toMatchObject({
      typical: 25,
      typicalN: 4,
      floor: 17.5,
    });
    expect(stats.total?.se).toBeCloseTo(6.455, 3);
  });

  it("gives phase rows the same typical value", () => {
    const rows = [
      entry("a", "2027test_qm1", { autoFuelScored: 4, dieCard: true }),
      entry("b", "2027test_qm2", { autoFuelScored: 10 }),
      entry("c", "2027test_qm3", { autoFuelScored: 20 }),
    ];
    const phases = phaseStats(config, rows);
    expect(phases.auto).toMatchObject({ typical: 15, typicalN: 2 });
    expect(phases.auto?.se).toBeCloseTo(5, 5);
  });

  it("leaves out a match far from the team's usual and names it", () => {
    const stats = genericStats([40, 42, 41, 43, 5, 41].map((n) => play(n)));
    expect(stats.total?.leftOut).toEqual([
      { key: "2027test_qm5", value: 5, reason: "low" },
    ]);
    expect(stats.total?.typical).toBeCloseTo(41.4, 5);
    expect(stats.total?.mean).toBeCloseTo(212 / 6, 5);
  });

  it("lists breakdown matches among the matches left out", () => {
    const stats = genericStats([play(10), play(12), play(0, { q1: true })]);
    expect(stats.total?.leftOut).toEqual([
      { key: "2027test_qm3", value: 0, reason: "breakdown" },
    ]);
  });

  it("takes the trend from matches without a breakdown", () => {
    const rows = [
      ...[10, 11, 10, 11, 10, 11].map((n) => play(n)),
      play(0, { q1: true }),
      play(0, { q1: true }),
    ];
    expect(genericStats(rows).trend?.direction).toBe("steady");
    expect(genericStats(rows.slice(0, 5)).trend).toBeNull();
  });
});

describe("rate rows", () => {
  it("counts a successful climb out of the matches with an answer", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { eLow: "Successful" }),
      entry("b", "2027test_qm2", { eLow: "Failed" }),
      entry("c", "2027test_qm3", { eLow: "N/A" }),
      entry("d", "2027test_qm4", { eLow: "Depot" }),
    ]);
    expect(rate(stats, "eLow")).toMatchObject({
      label: "Low Climb (L1)",
      successes: 2,
      total: 4,
    });
  });

  it("counts a boolean as a yes in a match when most scouts said yes", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { tRdefense: true }),
      entry("b", "2027test_qm1", { tRdefense: true }),
      entry("c", "2027test_qm1", { tRdefense: false }),
      entry("d", "2027test_qm2", { tRdefense: true }),
      entry("e", "2027test_qm2", { tRdefense: false }),
    ]);
    expect(rate(stats, "tRdefense")).toMatchObject({ successes: 1, total: 2 });
  });

  it("makes no rate of a category select", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { robot: "R1", starting: "Center Hub" }),
    ]);
    expect(rate(stats, "robot")).toBeUndefined();
    expect(rate(stats, "starting")).toBeUndefined();
  });

  it("reads a card select as a rate of matches with a card", () => {
    const stats = computeStats(config, [
      entry("a", "2027test_qm1", { ryCard: "None" }),
      entry("b", "2027test_qm2", { ryCard: "Yellow" }),
      entry("c", "2027test_qm3", { ryCard: "false" }),
    ]);
    expect(rate(stats, "ryCard")).toMatchObject({ successes: 1, total: 3 });
  });
});

describe("action tracker counts", () => {
  const tracked = parseConfig({
    title: "t",
    revision: 1,
    sections: [
      {
        name: "Teleop",
        fields: [
          {
            title: "Track",
            code: "track",
            type: "action-tracker",
            actions: [{ code: "pass", label: "Pass" }],
          },
        ],
      },
    ],
  });

  it("gets a row per action from the derived count key", () => {
    const stats = computeStats(tracked, [
      entry("a", "2027test_qm1", { track_pass_count: 2 }),
      entry("b", "2027test_qm2", { track_pass_count: 4 }),
    ]);
    expect(row(stats, "track_pass_count")).toMatchObject({
      label: "Pass",
      mean: 3,
      n: 2,
    });
    expect(stats.series).toEqual([]);
  });
});

describe("groupByMatch", () => {
  it("groups by key and sorts by play order", () => {
    const groups = groupByMatch([
      entry("a", "2027test_qm2", {}),
      entry("b", "2027test_qm1", {}),
      entry("c", "2027test_qm2", {}),
    ]);
    expect(groups.map((g) => [g.key, g.entries.length])).toEqual([
      ["2027test_qm1", 1],
      ["2027test_qm2", 2],
    ]);
  });
});
