import { describe, expect, it } from "vitest";
import { applyCorrections } from "../corrections/apply";
import type { AllianceFuel } from "../data/tbaBreakdown";
import {
  type AccuracyEntry,
  bandOf,
  buildReport,
  countOf,
  formatMiss,
  scoutOf,
  solveRidge,
} from "./opr";

const key = (n: number) => `2027test_qm${n}`;

function entry(
  match: number,
  team: number,
  scout: string,
  auto: number,
  teleop: number,
  extra: Partial<AccuracyEntry> = {},
): AccuracyEntry {
  return {
    tbaMatchKey: key(match),
    teamNumber: team,
    rawValues: { autoFuelScored: auto, teleopFuelScored: teleop },
    scoutedByName: scout,
    ...extra,
  };
}

const official = (
  match: number,
  alliance: "red" | "blue",
  teams: number[],
  count: number,
): AllianceFuel => ({ matchKey: key(match), alliance, teams, count });

describe("solveRidge", () => {
  it("splits one equation's error evenly, shrunk by lambda", () => {
    const b = solveRidge([[0, 1, 2]], [8], 3);
    for (const v of b) expect(v).toBeCloseTo(2, 10);
  });

  it("separates a careless scout from careful partners", () => {
    const rows = [
      [0, 1, 2],
      [0, 3, 4],
      [0, 5, 1],
      [1, 2, 3],
      [2, 4, 5],
      [3, 5, 4],
    ];
    const truth = [9, 0, 0, 0, 0, 0];
    const errors = rows.map((r) =>
      r.reduce((sum, i) => sum + (truth[i] as number), 0),
    );
    const b = solveRidge(rows, errors, 6, 0.01);
    expect(b[0]).toBeGreaterThan(8);
    for (const v of b.slice(1)) expect(Math.abs(v)).toBeLessThan(2);
  });
});

describe("scoutOf", () => {
  it("prefers the credited scout, then the typed field, then the author", () => {
    const base = { tbaMatchKey: key(1), teamNumber: 1111 };
    const raw = { scouter: " Typed  Name " };
    expect(
      scoutOf({
        ...base,
        rawValues: raw,
        scoutedByName: "Credit",
        authorDisplayName: "Author",
      }),
    ).toBe("Credit");
    expect(
      scoutOf({ ...base, rawValues: raw, authorDisplayName: "Author" }),
    ).toBe("Typed Name");
    expect(
      scoutOf({ ...base, rawValues: {}, authorDisplayName: "Author" }),
    ).toBe("Author");
    expect(scoutOf({ ...base, rawValues: {}, scouterUid: "u9" })).toBe("u9");
    expect(scoutOf({ ...base, rawValues: {} })).toBeNull();
  });
});

describe("countOf", () => {
  const at = (rawValues: Record<string, unknown>) =>
    countOf({ tbaMatchKey: key(1), teamNumber: 1111, rawValues });

  it("adds auto and teleop, reading numeric strings", () => {
    expect(at({ autoFuelScored: 3, teleopFuelScored: "9" })).toBe(12);
    expect(at({ teleopFuelScored: 5 })).toBe(5);
  });

  it("is null with neither field or a value that is not a number", () => {
    expect(at({})).toBeNull();
    expect(at({ autoFuelScored: "many", teleopFuelScored: 4 })).toBeNull();
    expect(at({ autoFuelScored: "", teleopFuelScored: 4 })).toBeNull();
    expect(at({ autoFuelScored: true })).toBeNull();
  });
});

describe("bands and format", () => {
  it("uses 4 and 12 as the limits, edges included", () => {
    expect(bandOf(4)).toBe("ok");
    expect(bandOf(-4)).toBe("ok");
    expect(bandOf(4.01)).toBe("check-in");
    expect(bandOf(-12)).toBe("check-in");
    expect(bandOf(12.01)).toBe("coach");
  });

  it("signs the estimate with one decimal", () => {
    expect(formatMiss(3.24)).toBe("+3.2");
    expect(formatMiss(-3.26)).toBe("-3.3");
    expect(formatMiss(0.01)).toBe("0.0");
    expect(formatMiss(-0.04)).toBe("0.0");
  });
});

describe("buildReport", () => {
  const entries = [
    entry(1, 1111, "Scout A", 4, 8),
    entry(1, 2222, "Scout B", 2, 6),
    entry(1, 3333, "Scout C", 0, 6),
  ];
  const alliances = [official(1, "red", [1111, 2222, 3333], 34)];

  it("gives one equation per complete alliance and a ridge estimate", () => {
    const report = buildReport(entries, alliances);
    expect(report.equations).toBe(1);
    expect(report.averageCapture).toBeCloseTo(26 / 34, 10);
    expect(report.scouts.map((s) => s.name).sort()).toEqual([
      "Scout A",
      "Scout B",
      "Scout C",
    ]);
    for (const s of report.scouts) {
      expect(s.miss).toBeCloseTo(2, 10);
      expect(s.band).toBe("ok");
      expect(s.robots).toBe(1);
    }
  });

  it("keeps the matches behind each scout", () => {
    const [scout] = buildReport(entries, alliances).scouts;
    expect(scout?.used).toHaveLength(1);
    expect(scout?.used[0]).toMatchObject({
      matchKey: key(1),
      alliance: "red",
      official: 34,
      scouted: 26,
    });
  });

  it("counts an alliance with an unscouted robot as incomplete", () => {
    const report = buildReport(entries.slice(0, 2), alliances);
    expect(report.equations).toBe(0);
    expect(report.incomplete).toBe(1);
    expect(report.scouts).toEqual([]);
  });

  it("skips an alliance with a duplicate entry or an unusable one", () => {
    const duplicate = [...entries, entry(1, 3333, "Scout D", 1, 1)];
    expect(buildReport(duplicate, alliances).skipped).toBe(1);

    const nameless = [
      ...entries.slice(0, 2),
      {
        tbaMatchKey: key(1),
        teamNumber: 3333,
        rawValues: { autoFuelScored: 1, teleopFuelScored: 1 },
      },
    ];
    expect(buildReport(nameless, alliances).skipped).toBe(1);

    const noCount = [
      ...entries.slice(0, 2),
      entry(1, 3333, "Scout C", 0, 0, { rawValues: { x: 1 } }),
    ];
    expect(buildReport(noCount, alliances).skipped).toBe(1);
  });

  it("leaves out keyless entries and ones a lead keyed in by hand", () => {
    const keyless = [
      entries[0] as AccuracyEntry,
      entries[1] as AccuracyEntry,
      { ...(entries[2] as AccuracyEntry), tbaMatchKey: null },
    ];
    expect(buildReport(keyless, alliances).incomplete).toBe(1);
    const manual = [
      entries[0] as AccuracyEntry,
      entries[1] as AccuracyEntry,
      { ...(entries[2] as AccuracyEntry), addedManually: true },
    ];
    expect(buildReport(manual, alliances).incomplete).toBe(1);
  });

  it("joins a scout's spellings and matches the key in any case", () => {
    const messy = [
      { ...(entries[0] as AccuracyEntry), tbaMatchKey: key(1).toUpperCase() },
      entries[1] as AccuracyEntry,
      entry(1, 3333, " scout   a ", 0, 6),
    ];
    const report = buildReport(messy, alliances);
    expect(report.equations).toBe(1);
    expect(report.scouts).toHaveLength(2);
    expect(report.scouts.find((s) => s.robots === 2)?.name).toBe("Scout A");
  });

  it("dims a scout with fewer than six robots and ranks those last", () => {
    const rows: AccuracyEntry[] = [];
    const alliancesMany: AllianceFuel[] = [];
    for (let m = 1; m <= 6; m++) {
      const rare = m === 1 ? "Rare" : "Other";
      rows.push(
        entry(m, 1111, "Often", 0, 5),
        entry(m, 2222, rare, 0, 5),
        entry(m, 3333, `Filler ${m}`, 0, 5),
      );
      alliancesMany.push(official(m, "red", [1111, 2222, 3333], 40));
    }
    const { scouts } = buildReport(rows, alliancesMany);
    const often = scouts.find((s) => s.name === "Often");
    const rare = scouts.find((s) => s.name === "Rare");
    expect(often?.enough).toBe(true);
    expect(rare?.enough).toBe(false);
    expect(scouts.indexOf(often as never)).toBeLessThan(
      scouts.indexOf(rare as never),
    );
  });

  it("finds the one careless scout when partners rotate", () => {
    const names = ["Scout A", "Scout B", "Scout C", "Scout D", "Scout E"];
    const miss: Record<string, number> = { "Scout C": 10 };
    const rows: AccuracyEntry[] = [];
    const list: AllianceFuel[] = [];
    for (let m = 1; m <= 20; m++) {
      const teams = [1111, 2222, 3333];
      const picked = teams.map(
        (_, slot) => names[(m + slot * 2) % 5] as string,
      );
      let scouted = 0;
      let off = 0;
      teams.forEach((team, slot) => {
        const real = 10 + ((m * 3 + slot) % 5);
        const scout = picked[slot] as string;
        const counted = real - (miss[scout] ?? 0);
        rows.push(entry(m, team, scout, 0, counted));
        scouted += counted;
        off += real;
      });
      list.push(official(m, "red", teams, off));
      expect(off - scouted).toBeGreaterThanOrEqual(0);
    }
    const { scouts } = buildReport(rows, list);
    expect(scouts[0]?.name).toBe("Scout C");
    expect(scouts[0]?.miss).toBeGreaterThan(7);
    expect(scouts[0]?.band).not.toBe("ok");
    for (const s of scouts.slice(1)) expect(Math.abs(s.miss)).toBeLessThan(2);
  });

  it("reads the scout's own count, never a lead's correction", () => {
    const stored = [
      { id: "a", ...entry(1, 1111, "Scout A", 4, 8) },
      { id: "b", ...entry(1, 2222, "Scout B", 2, 6) },
      { id: "c", ...entry(1, 3333, "Scout C", 0, 6) },
    ].map((e) => ({ ...e, fieldValues: e.rawValues }));
    const corrected = applyCorrections(stored, [
      {
        id: "a",
        eventKey: "2027test",
        fields: { teleopFuelScored: 20 },
        note: "",
        authorUid: "u1",
        authorDisplayName: "Lead A",
        history: [],
        updatedMs: 1,
      },
    ]);
    expect(corrected[0]?.fieldValues.teleopFuelScored).toBe(20);
    expect(buildReport(corrected, alliances)).toEqual(
      buildReport(stored, alliances),
    );
  });
});
