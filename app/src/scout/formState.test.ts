import { describe, expect, it } from "vitest";
import { parseConfig } from "./config";
import { applySchedule, initForm, resetForNext, setValue } from "./formState";
import type { ScheduledMatch } from "./schedule";

const config = parseConfig({
  sections: [
    {
      name: "Pre",
      fields: [
        { code: "scouter", type: "text", formResetBehavior: "preserve" },
        { code: "matchNumber", type: "TBA-match-number", defaultValue: 1 },
        {
          code: "robot",
          type: "select",
          choices: { R1: "R1", R2: "R2", B1: "B1" },
          defaultValue: "R1",
          formResetBehavior: "preserve",
        },
        { code: "pTnumber", type: "number" },
      ],
    },
    {
      name: "Auto",
      fields: [
        { code: "fuel", type: "counter" },
        {
          code: "run",
          type: "number",
          defaultValue: 0,
          formResetBehavior: "increment",
        },
      ],
    },
  ],
});

const m = (n: number): ScheduledMatch => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red: [10 * n + 1, 10 * n + 2, 10 * n + 3],
  blue: [10 * n + 4, 10 * n + 5, 10 * n + 6],
});
const schedule = [m(1), m(2), m(3)];
const ctx = (
  saved: { tbaMatchKey: string | null; station: string }[] = [],
) => ({
  config,
  schedule,
  saved,
});

describe("initForm", () => {
  it("uses the device station and fills match and team from the schedule", () => {
    const f = initForm(ctx(), "R2");
    expect(f.values.robot).toBe("R2");
    expect(f.values.matchNumber).toBe("1");
    expect(f.values.pTnumber).toBe("12");
  });

  it("leaves the typed fields alone without a schedule", () => {
    const f = initForm({ config, schedule: [], saved: [] }, null);
    expect(f.values.robot).toBe("R1");
    expect(f.values.matchNumber).toBe(1);
    expect(f.values.pTnumber).toBe(0);
  });

  it("fills a late schedule only while the match is untouched", () => {
    const start = initForm({ config, schedule: [], saved: [] }, "B1");
    expect(applySchedule(start, ctx()).values.matchNumber).toBe("1");
    const typed = setValue(
      start,
      { config, schedule: [], saved: [] },
      "matchNumber",
      "7",
    );
    expect(applySchedule(typed, ctx()).values.matchNumber).toBe("7");
  });
});

describe("setValue", () => {
  it("refreshes the team when the match or station changes", () => {
    const f = initForm(ctx(), "R1");
    const next = setValue(f, ctx(), "matchNumber", "3");
    expect(next.values.pTnumber).toBe("31");
    const other = setValue(next, ctx(), "robot", "B1");
    expect(other.values.pTnumber).toBe("34");
  });

  it("re-anchors a scheduled match when the station changes", () => {
    const saved = [{ tbaMatchKey: "2027test_qm1", station: "R1" }];
    const f = initForm(ctx(saved), "R1");
    expect(f.values.matchNumber).toBe("2");
    const other = setValue(f, ctx(saved), "robot", "R2");
    expect(other.values.matchNumber).toBe("1");
  });

  it("keeps a typed match number when the station changes", () => {
    const f = initForm(ctx(), "R1");
    const typed = setValue(f, ctx(), "matchNumber", "3");
    expect(setValue(typed, ctx(), "robot", "R2").values.matchNumber).toBe("3");
  });
});

describe("resetForNext", () => {
  it("advances the match, applies each reset behavior and refills the team", () => {
    const saved = [{ tbaMatchKey: "2027test_qm1", station: "R1" }];
    let f = initForm(ctx(), "R1");
    f = setValue(f, ctx(), "scouter", "Sam");
    f = setValue(f, ctx(), "fuel", 9);
    const next = resetForNext(f, ctx(saved));
    expect(next.values.matchNumber).toBe("2");
    expect(next.values.pTnumber).toBe("21");
    expect(next.values.scouter).toBe("Sam");
    expect(next.values.robot).toBe("R1");
    expect(next.values.fuel).toBe(0);
    expect(next.values.run).toBe(1);
  });

  it("counts up by one when there is no schedule", () => {
    const bare = { config, schedule: [], saved: [] };
    let f = initForm(bare, "R1");
    f = setValue(f, bare, "matchNumber", "4");
    expect(resetForNext(f, bare).values.matchNumber).toBe("5");
  });
});
