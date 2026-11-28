import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { buildRows, formOf, signed } from "./rows";

const config = parseConfig(bundled);

function entry(
  id: string,
  team: number,
  match: number,
  auto: number,
  teleop: number,
  extra: Record<string, unknown> = {},
): EventEntry {
  return {
    id,
    tbaMatchKey: `2027test_qm${match}`,
    teamNumber: team,
    alliance: "Red",
    scoutName: "Scout A",
    updatedAt: "2027-03-01T12:00:00.000Z",
    fieldValues: {
      autoFuelScored: auto,
      teleopFuelScored: teleop,
      ...extra,
    },
  };
}

const teams = [
  { number: 1111, nickname: "Alpha" },
  { number: 2222, nickname: "Beta" },
  { number: 3333, nickname: "Gamma" },
];
const rankings = [
  { team: 2222, rank: 1, wins: 3, losses: 0, ties: 0 },
  { team: 1111, rank: 2, wins: 2, losses: 1, ties: 0 },
];

describe("buildRows", () => {
  it("joins the team list with rank, record, EPA and scouted stats", () => {
    const entries = [
      entry("a", 1111, 1, 4, 10),
      entry("b", 1111, 2, 6, 20),
      entry("c", 1111, 3, 2, 6, { eHigh: "Successful" }),
    ];
    const rows = buildRows({
      config,
      teams,
      rankings,
      entries,
      epa: { 1111: 31.5 },
    });
    const one = rows.find((r) => r.team === 1111);
    expect(one).toMatchObject({
      nickname: "Alpha",
      listed: true,
      rank: 2,
      record: "2-1-0",
      epa: 31.5,
      matches: 3,
      climb: 3,
    });
    expect(one?.series.map((p) => p.value)).toEqual([14, 26, 8]);
    expect(one?.total).toBe(16);
    expect(one?.auto).toBe(4);
    expect(one?.teleop).toBe(12);
    expect(one?.sd).not.toBeNull();
    expect(one?.form).toBeNull();
    const none = rows.find((r) => r.team === 3333);
    expect(none).toMatchObject({
      rank: null,
      epa: null,
      matches: 0,
      total: null,
      climb: 0,
    });
  });

  it("keeps a far outlier out of the score but in the plain average", () => {
    const entries = [40, 42, 41, 43, 41, 90].map((teleop, i) =>
      entry(`m${i}`, 1111, i + 1, 0, teleop),
    );
    const one = buildRows({
      config,
      teams,
      rankings: [],
      entries,
      epa: null,
    }).find((r) => r.team === 1111);
    expect(one?.total).toBeCloseTo(41.4, 5);
    expect(one?.teleop).toBeCloseTo(41.4, 5);
    expect(one?.mean.total).toBeCloseTo(49.5, 5);
    expect(one?.mean.teleop).toBeCloseTo(49.5, 5);
    expect(one?.mean.auto).toBe(0);
  });

  it("leaves the spread out below three matches", () => {
    const rows = buildRows({
      config,
      teams,
      rankings: [],
      entries: [entry("a", 1111, 1, 4, 10), entry("b", 1111, 2, 5, 10)],
      epa: null,
    });
    expect(rows.find((r) => r.team === 1111)?.sd).toBeNull();
  });

  it("counts a match scouted twice once", () => {
    const rows = buildRows({
      config,
      teams,
      rankings: [],
      entries: [entry("a", 1111, 1, 4, 10), entry("b", 1111, 1, 6, 10)],
      epa: null,
    });
    const one = rows.find((r) => r.team === 1111);
    expect(one?.matches).toBe(1);
    expect(one?.series[0]?.value).toBe(5 + 10);
  });

  it("adds a scouted team missing from the team list, marked unlisted", () => {
    const rows = buildRows({
      config,
      teams,
      rankings: [],
      entries: [entry("a", 9999, 1, 1, 1)],
      epa: null,
    });
    expect(rows.find((r) => r.team === 9999)).toMatchObject({
      nickname: "",
      listed: false,
      matches: 1,
    });
  });

  it("falls back to rankings and EPA when TBA gave no team list", () => {
    const rows = buildRows({
      config,
      teams: [],
      rankings,
      entries: [],
      epa: { 4444: 20 },
    });
    expect(rows.map((r) => r.team).sort()).toEqual([1111, 2222, 4444]);
    expect(rows.every((r) => r.listed)).toBe(true);
  });

  it("treats an EPA of zero as none", () => {
    const rows = buildRows({
      config,
      teams,
      rankings: [],
      entries: [],
      epa: { 1111: 0 },
    });
    expect(rows.find((r) => r.team === 1111)?.epa).toBeNull();
  });

  it("scores a team by its average without breakdown matches, with floor and reliability", () => {
    const rows = buildRows({
      config,
      teams,
      rankings: [],
      entries: [
        entry("a", 1111, 1, 0, 10, { dieCard: false }),
        entry("b", 1111, 2, 0, 20, { dieCard: false }),
        entry("c", 1111, 3, 0, 30, { dieCard: false }),
        entry("d", 1111, 4, 0, 40, { dieCard: false }),
        entry("e", 1111, 5, 0, 0, { dieCard: true }),
      ],
      epa: null,
    });
    const one = rows.find((r) => r.team === 1111);
    expect(one?.total).toBe(25);
    expect(one?.totalSe).toBeCloseTo(6.455, 3);
    expect(one?.floor).toBe(17.5);
    expect(one?.reliability).toEqual({ ok: 4, of: 5 });
    expect(one?.teleop).toBe(25);
    expect(one?.teleopSe).toBeCloseTo(6.455, 3);
    expect(one?.iqm).toEqual({ total: 20, auto: 0, teleop: 20 });
    const none = rows.find((r) => r.team === 3333);
    expect(none).toMatchObject({ floor: null, reliability: null });
  });

  it("reads the stats from corrected values", () => {
    const fixed: EventEntry = {
      ...entry("a", 1111, 1, 4, 10),
      fieldValues: { autoFuelScored: 9, teleopFuelScored: 10 },
    };
    const rows = buildRows({
      config,
      teams,
      rankings: [],
      entries: [fixed],
      epa: null,
    });
    expect(rows.find((r) => r.team === 1111)?.auto).toBe(9);
  });
});

describe("formOf", () => {
  const series = (...values: number[]) =>
    values.map((value, i) => ({ key: `2027test_qm${i + 1}`, value }));

  it("needs five scored matches", () => {
    expect(formOf(series(1, 2, 3, 4))).toBeNull();
  });

  it("is the last three against the matches before", () => {
    expect(formOf(series(10, 10, 16, 16, 16))).toBe(6);
    expect(formOf(series(20, 20, 14, 14, 14))).toBe(-6);
  });
});

describe("signed", () => {
  it("shows a plus on a gain", () => {
    expect(signed(3)).toBe("+3");
    expect(signed(-1.5)).toBe("-1.5");
    expect(signed(0)).toBe("0");
  });
});
