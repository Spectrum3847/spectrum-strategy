import { describe, expect, it } from "vitest";
import { emptyBrief } from "../match/brief";
import type { ScheduledMatch } from "../scout/schedule";
import { briefStatus, coverage, lastResult } from "./lead";

const qm = (
  n: number,
  played: boolean,
  red = [1111, 2222, 3333],
  blue = [4444, 5555, 6666],
  scores: [number, number] = [40, 30],
): ScheduledMatch => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red,
  blue,
  redScore: played ? scores[0] : -1,
  blueScore: played ? scores[1] : -1,
});

const entry = (
  id: string,
  team: number,
  tbaMatchKey: string | null,
  fieldValues: Record<string, unknown> = {},
) => ({ id, teamNumber: team, tbaMatchKey, fieldValues });

describe("lastResult", () => {
  it("reports the latest played match as a win, loss or tie", () => {
    const schedule = [
      qm(1, true),
      qm(2, true, [1111, 7, 8], [9, 10, 11], [20, 50]),
      qm(3, false),
    ];
    expect(lastResult(schedule, 1111)).toMatchObject({
      label: "Q2",
      alliance: "Red",
      ours: 20,
      theirs: 50,
      outcome: "lost",
    });
    expect(lastResult([qm(1, true)], 4444)).toMatchObject({
      alliance: "Blue",
      ours: 30,
      theirs: 40,
      outcome: "lost",
    });
    expect(
      lastResult([qm(1, true, undefined, undefined, [35, 35])], 1111),
    ).toMatchObject({ outcome: "tied" });
    expect(lastResult([qm(1, true)], 1111)).toMatchObject({ outcome: "won" });
  });

  it("is null before we have played", () => {
    expect(lastResult([qm(1, false)], 1111)).toBeNull();
    expect(lastResult([qm(1, true)], 9999)).toBeNull();
  });
});

describe("briefStatus", () => {
  const draft = {
    ...emptyBrief("2027test", "qm3"),
    keyPoints: "Play defense",
  };
  it("tells ready, draft and none apart", () => {
    expect(briefStatus([], "2027test", "2027test_qm3")).toBe("none");
    expect(briefStatus([draft], "2027test", "2027test_qm3")).toBe("draft");
    expect(
      briefStatus([{ ...draft, ready: true }], "2027test", "2027test_qm3"),
    ).toBe("ready");
    expect(briefStatus([draft], "2027test", "2027test_qm4")).toBe("none");
  });

  it("counts an empty brief that is not ready as none", () => {
    expect(
      briefStatus([emptyBrief("2027test", "qm3")], "2027test", "2027test_qm3"),
    ).toBe("none");
  });
});

describe("coverage", () => {
  it("has nothing to check before a qualification match is played", () => {
    expect(coverage([qm(1, false)], [])).toMatchObject({
      through: null,
      gaps: [],
    });
  });

  it("lists robots with no entry in the played matches", () => {
    const schedule = [qm(1, true), qm(2, true), qm(3, false)];
    const entries = [
      entry("a", 1111, "2027test_qm1"),
      entry("b", 2222, "2027TEST_QM1"),
      entry("c", 3333, "2027test_qm1"),
      entry("d", 4444, "2027test_qm1"),
      entry("e", 5555, "2027test_qm1"),
      entry("f", 6666, "2027test_qm1"),
      entry("g", 1111, "2027test_qm2"),
    ];
    const result = coverage(schedule, entries);
    expect(result.through).toBe(2);
    expect(result.gaps).toHaveLength(1);
    expect(result.gaps[0]).toMatchObject({
      label: "Q2",
      teams: [2222, 3333, 4444, 5555, 6666],
    });
    expect(result.robots).toBe(5);
  });

  it("counts an entry with a typed match number and no TBA key", () => {
    const schedule = [qm(1, true, [1, 2, 3], [4, 5, 6])];
    const typed = [1, 2, 3, 4, 5, 6].map((t) =>
      entry(`t${t}`, t, null, { matchNumber: 1 }),
    );
    expect(coverage(schedule, typed).gaps).toEqual([]);
  });

  it("looks only at the last ten played qualification matches", () => {
    const schedule = Array.from({ length: 14 }, (_, i) => qm(i + 1, true));
    const result = coverage(schedule, []);
    expect(result.from).toBe(5);
    expect(result.through).toBe(14);
    expect(result.gaps).toHaveLength(10);
    expect(result.gaps[0]?.label).toBe("Q5");
  });

  it("ignores matches not played, even before the last played one", () => {
    const schedule = [qm(1, true), qm(2, false), qm(3, true), qm(4, false)];
    expect(coverage(schedule, []).gaps.map((g) => g.label)).toEqual([
      "Q1",
      "Q3",
    ]);
  });
});
