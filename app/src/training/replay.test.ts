import { describe, expect, it } from "vitest";
import type { ScheduledMatch } from "../scout/schedule";
import {
  buildReplay,
  eventMatchesFrom,
  nextLabel,
  rankingsAt,
  scheduleAt,
} from "./replay";

const match = (
  key: string,
  number: number,
  red: number[],
  blue: number[],
  redScore: number,
  blueScore: number,
  compLevel = "qm",
): ScheduledMatch => ({
  key: `2026test_${key}`,
  compLevel,
  matchNumber: number,
  red,
  blue,
  time: 1000,
  predictedTime: 1100,
  redScore,
  blueScore,
});

const matches = [
  match("qm2", 2, [1111, 2222, 3333], [4444, 5555, 6666], 30, 30),
  match("qm1", 1, [1111, 4444, 3333], [2222, 5555, 6666], 50, 20),
  match("qm3", 3, [1111, 2222, 3333], [4444, 5555, 6666], -1, -1),
  match("sf1m1", 1, [1111], [2222], 40, 60, "sf"),
];

describe("buildReplay", () => {
  const replay = buildReplay(matches, []);

  it("keeps only matches with a result, in play order", () => {
    expect(replay.matches.map((m) => m.key)).toEqual([
      "2026test_qm1",
      "2026test_qm2",
      "2026test_sf1m1",
    ]);
  });

  it("drops clock times so nothing reads as overdue", () => {
    expect(replay.matches.every((m) => m.time === null)).toBe(true);
    expect(replay.matches.every((m) => m.predictedTime === null)).toBe(true);
  });
});

describe("scheduleAt", () => {
  const replay = buildReplay(matches, []);

  it("hides the score of every match not yet played", () => {
    const schedule = scheduleAt(replay, 1);
    expect(schedule[0]?.redScore).toBe(50);
    expect(schedule[1]?.redScore).toBe(-1);
    expect(schedule[2]?.blueScore).toBe(-1);
  });

  it("shows no score at the start", () => {
    expect(scheduleAt(replay, 0).every((m) => m.redScore === -1)).toBe(true);
  });

  it("does not change the replay it reads", () => {
    scheduleAt(replay, 0);
    expect(replay.matches[0]?.redScore).toBe(50);
  });
});

describe("eventMatchesFrom", () => {
  it("names the winner and leaves unplayed matches without scores", () => {
    const replay = buildReplay(matches, []);
    const [first, second, third] = eventMatchesFrom(scheduleAt(replay, 2));
    expect(first).toMatchObject({ winner: "red", redScore: 50 });
    expect(second).toMatchObject({ winner: null, redScore: 30 });
    const unplayed = eventMatchesFrom(scheduleAt(replay, 0));
    expect(unplayed[0]).toMatchObject({ winner: null, redScore: null });
    expect(third?.level).toBe("sf");
  });
});

describe("rankingsAt", () => {
  const replay = buildReplay(matches, []);

  it("is empty before a qualification match is played", () => {
    expect(rankingsAt(scheduleAt(replay, 0))).toEqual([]);
  });

  it("ranks by wins and ties from the revealed qualifications", () => {
    const ranks = rankingsAt(scheduleAt(replay, 2));
    const byTeam = new Map(ranks.map((r) => [r.team, r]));
    expect(byTeam.get(1111)).toMatchObject({ wins: 1, ties: 1, rank: 1 });
    expect(byTeam.get(2222)).toMatchObject({ losses: 1, ties: 1 });
    expect(ranks.reduce((n, r) => n + r.wins + r.losses + r.ties, 0)).toBe(12);
  });
});

describe("nextLabel", () => {
  const replay = buildReplay(matches, []);

  it("names the match Play next match reveals", () => {
    expect(nextLabel(replay, 0)).toBe("Q1");
    expect(nextLabel(replay, 2)).toBe("SF1");
  });

  it("is null once everything is played", () => {
    expect(nextLabel(replay, 3)).toBeNull();
  });
});
