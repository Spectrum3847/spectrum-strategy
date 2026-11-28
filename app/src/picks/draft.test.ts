import { describe, expect, it } from "vitest";
import {
  backups,
  canInvite,
  type DraftAction,
  isComplete,
  picksUntil,
  replayDraft,
  roundOf,
  roundsForEventType,
  seeding,
  takenLabels,
} from "./draft";

const ranking = Array.from({ length: 30 }, (_, i) => i + 1);
const pick = (team: number): DraftAction => ({ team, declined: false });
const decline = (team: number): DraftAction => ({ team, declined: true });

describe("replayDraft", () => {
  it("seats the top eight as captains with alliance 1 on the clock", () => {
    const board = replayDraft([], ranking, 3);
    expect(board.alliances.map((a) => a.captain)).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8,
    ]);
    expect(board.picking).toBe(0);
    expect(roundOf(board)).toBe(0);
  });

  it("runs the snake: 1 to 8, then 8 to 1", () => {
    const first = Array.from({ length: 8 }, (_, i) => pick(9 + i));
    const board = replayDraft(first, ranking, 3);
    expect(board.picking).toBe(7);
    expect(roundOf(board)).toBe(1);
    expect(board.alliances[0]?.picks).toEqual([9]);
    expect(board.alliances[7]?.picks).toEqual([16]);
  });

  it("moves the alliances up when a captain accepts, and seats the best free team", () => {
    const board = replayDraft([pick(5)], ranking, 3);
    expect(board.alliances.map((a) => a.captain)).toEqual([
      1, 2, 3, 4, 6, 7, 8, 9,
    ]);
    expect(board.alliances[0]?.teams).toEqual([1, 5]);
    expect(board.taken.has(9)).toBe(true);
  });

  it("records a decline without using the pick", () => {
    const board = replayDraft([decline(9), pick(10)], ranking, 3);
    expect(board.declined.has(9)).toBe(true);
    expect(board.alliances[0]?.picks).toEqual([10]);
    expect(canInvite(board, 9)).toBe(false);
  });

  it("skips an action that is not legal, such as a team already taken", () => {
    const board = replayDraft([pick(9), pick(9), pick(10)], ranking, 3);
    expect(board.alliances[0]?.picks).toEqual([9]);
    expect(board.alliances[1]?.picks).toEqual([10]);
  });

  it("is complete after every round, and undo is a shorter log", () => {
    const log = Array.from({ length: 16 }, (_, i) => pick(9 + i));
    const done = replayDraft(log, ranking, 2);
    expect(isComplete(done)).toBe(true);
    const undone = replayDraft(log.slice(0, -1), ranking, 2);
    expect(isComplete(undone)).toBe(false);
    expect(undone.picking).toBe(0);
  });
});

describe("picksUntil", () => {
  it("counts the picks before an alliance is on the clock", () => {
    const board = replayDraft([], ranking, 3);
    expect(picksUntil(board, 1)).toBe(0);
    expect(picksUntil(board, 4)).toBe(3);
    expect(picksUntil(board, 99)).toBeNull();
  });

  it("counts down the snake", () => {
    const board = replayDraft(
      Array.from({ length: 8 }, (_, i) => pick(9 + i)),
      ranking,
      3,
    );
    expect(picksUntil(board, 8)).toBe(0);
    expect(picksUntil(board, 1)).toBe(7);
  });
});

describe("backups", () => {
  const log = Array.from({ length: 16 }, (_, i) => pick(9 + i));

  it("lists the best free official ranks after a two round draft", () => {
    const board = replayDraft(log, ranking, 2);
    expect(backups(board, ranking)).toEqual([25, 26, 27, 28, 29, 30]);
  });

  it("has none in a three round draft or before it ends", () => {
    expect(backups(replayDraft([], ranking, 2), ranking)).toEqual([]);
    expect(
      backups(
        replayDraft([...log, ...log.map((a) => pick(a.team + 16))], ranking, 3),
        ranking,
      ),
    ).toEqual([]);
  });
});

describe("labels and seeding", () => {
  it("says where the draft took each team", () => {
    const labels = takenLabels(replayDraft([pick(9)], ranking, 3));
    expect(labels.get(1)).toBe("Captain of alliance 1");
    expect(labels.get(9)).toBe("Picked by alliance 1");
  });

  it("seeds by official rank, then EPA, then team number", () => {
    expect(seeding([30, 10], { 20: 50, 40: 90 }, [10, 20, 30, 40, 50])).toEqual(
      [30, 10, 40, 20, 50],
    );
    expect(seeding([], null, [3, 1, 2])).toEqual([1, 2, 3]);
  });

  it("sets the rounds from the TBA event type", () => {
    expect(roundsForEventType(0)).toBe(2);
    expect(roundsForEventType(1)).toBe(2);
    expect(roundsForEventType(3)).toBe(3);
    expect(roundsForEventType(4)).toBe(3);
    expect(roundsForEventType(null)).toBe(3);
  });
});
