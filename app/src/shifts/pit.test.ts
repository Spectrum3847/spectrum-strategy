import { describe, expect, it } from "vitest";
import { includes, type PitShift, parsePitSchedule, rangeText } from "./pit";

const doc = {
  eventKey: "2027test",
  competition: "Test",
  syncedAt: "2027-03-05T18:00:00.000Z",
  shifts: [
    {
      id: "a",
      label: "Pit duty",
      kind: "pitDuty",
      assignees: [{ name: "Scout A", uid: "u1" }, { name: "Scout B" }],
      startMatch: 1,
      endMatch: 20,
    },
    {
      id: "b",
      label: "",
      kind: "loadIn",
      assignees: [],
      startsAt: "2027-03-05T14:00:00.000Z",
      endsAt: "2027-03-05T15:30:00.000Z",
    },
    "junk",
  ],
};

describe("parsePitSchedule", () => {
  it("reads the mirror document and skips junk", () => {
    const s = parsePitSchedule(doc);
    expect(s?.shifts).toHaveLength(2);
    expect(s?.shifts[0]?.assignees).toEqual([
      { name: "Scout A", uid: "u1" },
      { name: "Scout B", uid: null },
    ]);
    expect(s?.syncedAt?.toISOString()).toBe("2027-03-05T18:00:00.000Z");
  });

  it("is null for no document", () => {
    expect(parsePitSchedule(null)).toBeNull();
    expect(parsePitSchedule("x")).toBeNull();
  });
});

describe("shift text", () => {
  const shifts = (parsePitSchedule(doc)?.shifts ?? []) as [PitShift, PitShift];
  it("writes a match range, one match, or a time range", () => {
    expect(rangeText(shifts[0])).toBe("Q1-20");
    expect(rangeText({ ...shifts[0], endMatch: 1 })).toBe("Q1");
    expect(rangeText(shifts[1])).toContain(" to ");
    expect(rangeText({ ...shifts[1], startsAt: null, endsAt: null })).toBe("");
  });

  it("matches an assignee by uid only", () => {
    expect(includes(shifts[0], "u1")).toBe(true);
    expect(includes(shifts[0], "u2")).toBe(false);
  });
});
