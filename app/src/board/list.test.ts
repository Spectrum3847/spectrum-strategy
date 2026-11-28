import { describe, expect, it } from "vitest";
import {
  boardInScope,
  boardTitle,
  isPracticeBoard,
  localSessions,
  parseTeamList,
  practiceBoard,
  scheduledClash,
  scopeBoards,
  sharedTeams,
} from "./list";
import { boardSides, newSession, type Session, sessionJson } from "./model";

const board = (
  id: string,
  eventKey: string,
  updatedMs: number,
  extra: Partial<Session> = {},
): Session => ({
  ...newSession({
    id,
    eventKey,
    matchNumber: 5,
    alliance: "Red",
    teamNumbers: [],
    fieldId: "f",
    author: { uid: "u1", displayName: "Lead A" },
    nowMs: updatedMs,
  }),
  ...extra,
});

describe("boardTitle", () => {
  it("names the event and the match, or just the match", () => {
    expect(boardTitle(board("a", "", 1))).toBe("Match 5");
    expect(boardTitle(board("a", "", 1, { eventName: " Practice " }))).toBe(
      "Practice - Match 5",
    );
  });
});

describe("boardInScope", () => {
  const scope = (selected: string, board: string, only: boolean) =>
    boardInScope({
      selectedEventKey: selected,
      boardEventKey: board,
      thisEventOnly: only,
    });
  it("keeps everything when not scoping or when no event is set", () => {
    expect(scope("2027a", "2027b", false)).toBe(true);
    expect(scope("", "2027b", true)).toBe(true);
  });
  it("keeps a board with no event key either way", () => {
    expect(scope("2027a", "", true)).toBe(true);
  });
  it("otherwise needs the same event", () => {
    expect(scope("2027a", "2027a", true)).toBe(true);
    expect(scope("2027a", "2027b", true)).toBe(false);
  });
});

describe("scopeBoards", () => {
  const local = [
    board("mine-a", "2027a", 30),
    board("mine-b", "2027b", 20),
    board("mine-none", "", 10),
  ];
  const remote = [
    board("mine-a", "2027a", 30),
    board("team-a", "2027a", 50, { authorDisplayName: "Lead B" }),
    board("team-b", "2027b", 40),
    board("mine-b", "2027b", 20),
  ];

  it("lists device boards and team boards, newest first", () => {
    const out = scopeBoards({
      local,
      remote,
      selectedEventKey: "2027a",
      thisEventOnly: false,
    });
    expect(out.mine.map((b) => b.id)).toEqual([
      "mine-a",
      "mine-b",
      "mine-none",
    ]);
    expect(out.team.map((b) => b.id)).toEqual(["team-a", "team-b"]);
    expect(out.hidden).toBe(0);
  });

  it("filters to this event, keeps unplaceable boards, and counts the hidden", () => {
    const out = scopeBoards({
      local,
      remote,
      selectedEventKey: "2027a",
      thisEventOnly: true,
    });
    expect(out.mine.map((b) => b.id)).toEqual(["mine-a", "mine-none"]);
    expect(out.team.map((b) => b.id)).toEqual(["team-a"]);
    expect(out.hidden).toBe(2);
  });

  it("never lists a board twice when its device copy is filtered out", () => {
    const out = scopeBoards({
      local,
      remote,
      selectedEventKey: "2027a",
      thisEventOnly: true,
    });
    expect(out.team.map((b) => b.id)).not.toContain("mine-b");
    expect(out.hidden).toBe(2);
  });
});

describe("localSessions", () => {
  it("reads one board per id, newest copy winning", () => {
    const old = board("a", "2027a", 10);
    const fresh = board("a", "2027a", 20);
    const found = localSessions(
      [
        { key: "2027a|5", record: { doc: sessionJson(old), queuedMs: 0 } },
        { key: "id|a", record: { doc: sessionJson(fresh), queuedMs: 0 } },
      ],
      "f",
    );
    expect(found).toHaveLength(1);
    expect(found[0]?.key).toBe("id|a");
  });
});

describe("practiceBoard", () => {
  it("is an ordinary board document with the typed name", () => {
    const made = practiceBoard({
      id: "p1",
      matchNumber: 12,
      alliance: "Blue",
      name: " Scrimmage ",
      teams: [3333, 1111],
      opponents: [],
      eventKey: "2027a",
      fieldId: "f",
      author: { uid: "u1", displayName: "Lead A" },
      nowMs: 99,
    });
    expect(made).toMatchObject({
      id: "p1",
      eventKey: "2027a",
      eventName: "Scrimmage",
      matchNumber: 12,
      alliance: "Blue",
      teamNumbers: [1111, 3333],
      opponentTeams: [],
      authorUid: "u1",
      updatedMs: 99,
    });
    expect(boardTitle(made)).toBe("Scrimmage - Match 12");
  });

  it("records which teams are opponents and reopens with both sides", () => {
    const made = practiceBoard({
      id: "p2",
      matchNumber: 3,
      alliance: "Red",
      name: "",
      teams: [1111, 2222],
      opponents: [5555, 4444],
      eventKey: "2027a",
      fieldId: "f",
      author: { uid: "u1", displayName: "Lead A" },
      nowMs: 99,
    });
    expect(made.teamNumbers).toEqual([1111, 2222, 4444, 5555]);
    expect(made.opponentTeams).toEqual([4444, 5555]);
    const [held] = localSessions(
      [{ key: "id|p2", record: { doc: sessionJson(made), queuedMs: 0 } }],
      "f",
    );
    expect(boardSides(held?.session as Session)).toEqual({
      red: [1111, 2222],
      blue: [4444, 5555],
    });
  });
});

describe("sharedTeams", () => {
  it("lists teams typed on both sides", () => {
    expect(sharedTeams([1, 2, 3], [3, 4, 1])).toEqual([1, 3]);
    expect(sharedTeams([1], [2])).toEqual([]);
  });
});

describe("parseTeamList", () => {
  it("takes commas and spaces, drops repeats and caps at six", () => {
    expect(parseTeamList("1111, 2222 frc3333,1111").teams).toEqual([
      1111, 2222, 3333,
    ]);
    expect(parseTeamList("1,2,3,4,5,6,7,8").teams).toHaveLength(6);
    expect(parseTeamList("").teams).toEqual([]);
  });
  it("reports what is not a team number", () => {
    expect(parseTeamList("1111, abc, 0").bad).toEqual(["abc", "0"]);
  });
});

describe("scheduledClash", () => {
  const keys = ["2027a_qm5", "2027a_sf1m1"];
  it("finds the schedule match that would share the board", () => {
    expect(scheduledClash("2027a", 5, keys)).toBe("/matches/2027a_qm5");
  });
  it("is clear for a number not on the schedule, or with no event", () => {
    expect(scheduledClash("2027a", 12, keys)).toBeNull();
    expect(scheduledClash("", 5, keys)).toBeNull();
  });
});

describe("isPracticeBoard", () => {
  const opponents = board("p", "2027a", 1, { opponentTeams: [4444] });
  const bare = board("q", "2027a", 1);

  it("is never true for a board in the schedule", () => {
    expect(
      isPracticeBoard({
        session: opponents,
        scheduled: true,
        scheduleKnown: true,
      }),
    ).toBe(false);
  });

  it("is practice when the schedule was checked and has no such match", () => {
    expect(
      isPracticeBoard({ session: bare, scheduled: false, scheduleKnown: true }),
    ).toBe(true);
  });

  it("waits for the schedule unless the board names opponents", () => {
    expect(
      isPracticeBoard({
        session: bare,
        scheduled: false,
        scheduleKnown: false,
      }),
    ).toBe(false);
    expect(
      isPracticeBoard({
        session: opponents,
        scheduled: false,
        scheduleKnown: false,
      }),
    ).toBe(true);
  });
});
