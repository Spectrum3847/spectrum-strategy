import { describe, expect, it } from "vitest";
import type { ScheduledMatch } from "../scout/schedule";
import { parseMatches } from "../scout/tba";
import {
  awayText,
  compareMatches,
  formatTime,
  isPlayed,
  matchLabel,
  matchTime,
  timeLine,
} from "./matches";

const match = (
  key: string,
  compLevel: string,
  matchNumber: number,
  extra: Partial<ScheduledMatch> = {},
): ScheduledMatch => ({
  key,
  compLevel,
  matchNumber,
  red: [1111, 2222, 3333],
  blue: [4444, 5555, 6666],
  ...extra,
});

describe("compareMatches", () => {
  it("plays qualifications, then playoff sets in order", () => {
    const sorted = [
      match("2027test_f1m1", "f", 1),
      match("2027test_sf3m1", "sf", 1),
      match("2027test_qm10", "qm", 10),
      match("2027test_sf1m1", "sf", 1),
      match("2027test_qm2", "qm", 2),
      match("2027test_qf1m1", "qf", 1),
    ].sort(compareMatches);
    expect(sorted.map((m) => m.key)).toEqual([
      "2027test_qm2",
      "2027test_qm10",
      "2027test_qf1m1",
      "2027test_sf1m1",
      "2027test_sf3m1",
      "2027test_f1m1",
    ]);
  });
});

describe("matchLabel", () => {
  it("names qualifications and playoffs", () => {
    expect(matchLabel(match("2027test_qm12", "qm", 12))).toBe("Q12");
    expect(matchLabel(match("2027test_sf3m1", "sf", 1))).toBe("Semifinal 3");
    expect(matchLabel(match("2027test_qf2m2", "qf", 2))).toBe(
      "Quarterfinal 2 match 2",
    );
    expect(matchLabel(match("2027test_f1m2", "f", 2))).toBe("Final 2");
  });
});

describe("isPlayed", () => {
  it("is played once both scores are non-negative", () => {
    expect(isPlayed(match("k", "qm", 1, { redScore: 40, blueScore: 35 }))).toBe(
      true,
    );
    expect(isPlayed(match("k", "qm", 1, { redScore: 0, blueScore: 0 }))).toBe(
      true,
    );
    expect(isPlayed(match("k", "qm", 1, { redScore: -1, blueScore: -1 }))).toBe(
      false,
    );
  });

  it("reads a schedule cached without scores as not played", () => {
    expect(isPlayed(match("k", "qm", 1))).toBe(false);
  });
});

describe("times", () => {
  const utc = { locale: "en-US", timeZone: "UTC" };
  const sched = 1_803_055_320;
  const predicted = sched + 480;
  const now = new Date(sched * 1000);

  it("formats a same-day time and a time on another day", () => {
    expect(formatTime(sched, now, utc)).toBe("4:42 PM");
    expect(formatTime(sched + 86_400, now, utc)).toBe("Sat 4:42 PM");
  });

  it("prefers the prediction and keeps the schedule beside it", () => {
    const m = match("k", "qm", 1, { time: sched, predictedTime: predicted });
    expect(matchTime(m)).toEqual({ at: predicted, kind: "predicted" });
    expect(timeLine(m, now, utc)).toBe("Predicted 4:50 PM (scheduled 4:42 PM)");
  });

  it("falls back to the schedule and to nothing", () => {
    expect(timeLine(match("k", "qm", 1, { time: sched }), now, utc)).toBe(
      "Scheduled 4:42 PM",
    );
    expect(timeLine(match("k", "qm", 1), now, utc)).toBeNull();
    expect(
      timeLine(
        match("k", "qm", 1, { time: sched, predictedTime: sched }),
        now,
        utc,
      ),
    ).toBe("Predicted 4:42 PM");
  });
});

describe("awayText", () => {
  it("counts matches away", () => {
    expect(awayText(0)).toBe("Up next");
    expect(awayText(1)).toBe("1 match away");
    expect(awayText(4)).toBe("4 matches away");
  });
});

describe("parseMatches times and scores", () => {
  it("reads the scheduled and predicted time and both scores", () => {
    const [m] = parseMatches([
      {
        key: "2027test_qm1",
        comp_level: "qm",
        match_number: 1,
        time: 1000,
        predicted_time: 1100,
        alliances: {
          red: { team_keys: ["frc1111"], score: 50 },
          blue: { team_keys: ["frc2222"], score: -1 },
        },
      },
    ]);
    expect(m).toMatchObject({
      time: 1000,
      predictedTime: 1100,
      redScore: 50,
      blueScore: -1,
    });
  });

  it("reads a match with no times or scores as unplayed", () => {
    const [m] = parseMatches([
      {
        key: "2027test_qm1",
        comp_level: "qm",
        match_number: 1,
        time: null,
        alliances: { red: { team_keys: [] }, blue: { team_keys: [] } },
      },
    ]);
    expect(m).toMatchObject({
      time: null,
      predictedTime: null,
      redScore: -1,
      blueScore: -1,
    });
    expect(m && isPlayed(m)).toBe(false);
  });
});
