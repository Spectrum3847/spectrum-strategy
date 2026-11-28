import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { parseConfig } from "../scout/config";
import { computeStats, groupByMatch, type StatInput } from "./stats";
import { buildSummary, isEmptySummary } from "./summary";

const config = parseConfig(bundled);

const matches = (values: Record<string, unknown>[]): StatInput[] =>
  values.map((fieldValues, i) => ({
    id: `e${i}`,
    matchKey: `2027test_qm${i + 1}`,
    fieldValues,
  }));

function summarize(inputs: StatInput[]) {
  const stats = computeStats(config, inputs);
  return buildSummary(config, groupByMatch(inputs), stats);
}

const fuel = (values: number[]) =>
  matches(values.map((n) => ({ teleopFuelScored: n })));

describe("buildSummary", () => {
  it("says nothing for a team with no entries", () => {
    expect(isEmptySummary(summarize([]))).toBe(true);
  });

  it("claims no trend below six matches", () => {
    expect(summarize(fuel([1, 2, 3, 4, 5])).trend).toBeNull();
  });

  it("calls a clear rise in the second half improving and cites it", () => {
    const { trend } = summarize(fuel([10, 11, 10, 20, 21, 20]));
    expect(trend?.direction).toBe("improving");
    expect(trend?.line.text).toBe(
      "Improving: later matches average 20 against 10 earlier, more than normal swings",
    );
    expect(trend?.line.matches.map((m) => m.label)).toEqual(["Q4", "Q5", "Q6"]);
  });

  it("calls a clear fall declining and a flat run steady", () => {
    expect(summarize(fuel([20, 21, 20, 10, 11, 10])).trend?.direction).toBe(
      "declining",
    );
    const flat = summarize(fuel([10, 11, 10, 10, 11, 10])).trend;
    expect(flat?.direction).toBe("steady");
    expect(flat?.line.text).toBe("Steady: typically 10 ±0, usually 10 to 11");
  });

  it("does not call one big match a trend", () => {
    expect(summarize(fuel([10, 12, 9, 11, 10, 40])).trend?.direction).toBe(
      "steady",
    );
  });

  it("does not read late breakdowns as declining", () => {
    const inputs = matches([
      ...[20, 21, 20, 21, 20, 21].map((n) => ({
        teleopFuelScored: n,
        dieCard: false,
      })),
      { teleopFuelScored: 0, dieCard: true },
      { teleopFuelScored: 0, dieCard: true },
    ]);
    const summary = summarize(inputs);
    expect(summary.trend?.direction).toBe("steady");
    expect(summary.concerns[0]?.text).toBe("Disconnect/Die: 2 of 8 matches");
  });

  it("flags deaths and cards with a count and the matches", () => {
    const { concerns } = summarize(
      matches([
        { dieCard: true, ryCard: "Yellow" },
        { dieCard: false, ryCard: "None" },
        { dieCard: true, ryCard: "None" },
      ]),
    );
    expect(concerns).toEqual([
      {
        text: "Yellow/Red Card: 1 of 3 matches",
        matches: [{ key: "2027test_qm1", label: "Q1" }],
      },
      {
        text: "Disconnect/Die: 2 of 3 matches",
        matches: [
          { key: "2027test_qm1", label: "Q1" },
          { key: "2027test_qm3", label: "Q3" },
        ],
      },
    ]);
  });

  it("calls a climb reliable from three attempts at 80 percent", () => {
    const { strengths, concerns } = summarize(
      matches([
        { eLow: "Successful" },
        { eLow: "Successful" },
        { eLow: "N/A" },
        { eLow: "Successful" },
        { eLow: "Successful" },
        { eLow: "Failed" },
      ]),
    );
    expect(concerns).toEqual([]);
    expect(strengths[0]?.text).toBe(
      "Low Climb (L1): 4 of 5 attempts succeeded",
    );
    expect(strengths[0]?.matches).toHaveLength(4);
  });

  it("calls a climb unreliable under half and cites the failures", () => {
    const { concerns } = summarize(
      matches([
        { eLow: "Failed" },
        { eLow: "Successful" },
        { eLow: "Failed" },
        { eLow: "Failed" },
      ]),
    );
    expect(concerns[0]?.text).toBe("Low Climb (L1): 1 of 4 attempts succeeded");
    expect(concerns[0]?.matches.map((m) => m.label)).toEqual([
      "Q1",
      "Q3",
      "Q4",
    ]);
  });

  it("does not count a climb nobody tried as a failure", () => {
    const { concerns } = summarize(
      matches([{ eMiddle: "N/A" }, { eMiddle: "N/A" }, { eMiddle: "N/A" }]),
    );
    expect(concerns).toEqual([]);
  });

  it("names defense as a role when it is common enough", () => {
    const { roles } = summarize(
      matches([
        { tRdefense: true },
        { tRdefense: false },
        { tRdefense: false },
      ]),
    );
    expect(roles[0]?.text).toBe("Defense: 1 of 3 matches");
    const rare = summarize(
      matches([
        { tRdefense: true },
        ...Array.from({ length: 6 }, () => ({ tRdefense: false })),
      ]),
    );
    expect(rare.roles).toEqual([]);
  });
});
