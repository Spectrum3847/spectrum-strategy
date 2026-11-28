import { describe, expect, it } from "vitest";
import type { PitEntry } from "../data/parse";
import type { EventTeam } from "../data/tbaEvent";
import {
  isDuplicateRecord,
  ownPitEntry,
  pitRows,
  prescoutMatchLabel,
  prescoutRows,
  splitLegacyLabel,
} from "./entries";

function entry(over: Partial<PitEntry> & { id: string }): PitEntry {
  return {
    teamNumber: 1111,
    eventKey: "2027test",
    fieldValues: {},
    authorUid: "uid-a",
    scoutName: "Scout A",
    updatedAt: "2027-03-05T18:00:00.000Z",
    photoKeys: [],
    ...over,
  };
}

const teams: EventTeam[] = [
  { number: 1111, nickname: "Alpha" },
  { number: 2222, nickname: "Beta" },
  { number: 3333, nickname: "Gamma" },
];

describe("ownPitEntry", () => {
  const mine = entry({ id: "mine" });
  const theirs = entry({ id: "theirs", authorUid: "uid-b" });

  it("finds only the signed-in scout's entry for the team", () => {
    expect(ownPitEntry([theirs, mine], 1111, "uid-a", "2027test")?.id).toBe(
      "mine",
    );
    expect(ownPitEntry([theirs], 1111, "uid-a", "2027test")).toBeNull();
    expect(ownPitEntry([mine], 2222, "uid-a", "2027test")).toBeNull();
    expect(ownPitEntry([mine], 1111, null, "2027test")).toBeNull();
  });

  it("ignores an entry from another event", () => {
    const old = entry({ id: "old", eventKey: "2026other" });
    expect(ownPitEntry([old], 1111, "uid-a", "2027test")).toBeNull();
  });

  it("opens an entry with no event", () => {
    const legacy = entry({ id: "legacy", eventKey: "" });
    expect(ownPitEntry([legacy], 1111, "uid-a", "2027test")?.id).toBe("legacy");
  });

  it("prefers the event's entry, then the newest", () => {
    const legacy = entry({ id: "legacy", eventKey: "" });
    const newer = entry({ id: "newer", updatedAt: "2027-03-06T00:00:00.000Z" });
    expect(ownPitEntry([legacy, mine], 1111, "uid-a", "2027test")?.id).toBe(
      "mine",
    );
    expect(ownPitEntry([mine, newer], 1111, "uid-a", "2027test")?.id).toBe(
      "newer",
    );
  });
});

describe("pitRows", () => {
  const answered = { fieldValues: { a: "x" } };

  it("marks a team done only with answers and a photo for the event", () => {
    const rows = pitRows(
      teams,
      [
        entry({ id: "1", ...answered, photoKeys: ["k"] }),
        entry({
          id: "2",
          teamNumber: 2222,
          scoutName: "Scout B",
          ...answered,
          photoKeys: ["k"],
        }),
        entry({
          id: "3",
          teamNumber: 3333,
          eventKey: "2026other",
          ...answered,
          photoKeys: ["k"],
        }),
      ],
      "2027test",
    );
    expect(rows.map((r) => [r.team, r.done])).toEqual([
      [1111, true],
      [2222, true],
      [3333, false],
    ]);
    expect(rows[1]?.scouts).toEqual(["Scout B"]);
  });

  it("says what is missing", () => {
    const state = (entries: PitEntry[]) =>
      pitRows(teams.slice(0, 1), entries, "2027test")[0]?.state;
    expect(state([])).toBe("Not done");
    expect(state([entry({ id: "1", ...answered })])).toBe(
      "Form done, no photo",
    );
    expect(state([entry({ id: "1", photoKeys: ["k"] })])).toBe(
      "Photo, no form",
    );
    expect(
      state([entry({ id: "1", fieldValues: { a: "", b: false, c: [] } })]),
    ).toBe("Not done");
  });

  it("adds up the form and the photos across the team's entries", () => {
    const rows = pitRows(
      teams.slice(0, 1),
      [
        entry({ id: "1", ...answered }),
        entry({ id: "2", authorUid: "uid-b", photoKeys: ["k"] }),
      ],
      "2027test",
    );
    expect(rows[0]).toMatchObject({ done: true, state: "Done" });
  });
});

describe("prescout", () => {
  it("names a prescout match", () => {
    expect(prescoutMatchLabel("qual", " 16 ")).toBe("Q16");
    expect(prescoutMatchLabel("playoff", "7")).toBe("Playoff 7");
    expect(prescoutMatchLabel("final", "1")).toBe("Final 1");
    expect(prescoutMatchLabel(undefined, "Q3")).toBe("Q3");
    expect(prescoutMatchLabel("qual", "")).toBe("");
  });

  it("counts records per team for the event only", () => {
    const record = (id: string, team: number, over = {}) =>
      entry({
        id,
        teamNumber: team,
        fieldValues: { matchType: "qual", matchNumber: id },
        ...over,
      });
    const rows = prescoutRows(
      teams,
      [
        record("1", 1111),
        record("2", 1111),
        record("3", 1111),
        record("4", 1111),
        record("5", 1111, { scoutName: "Scout B" }),
        record("6", 2222),
        record("7", 2222, { eventKey: "2026other" }),
      ],
      "2027test",
    );
    expect(rows.map((r) => [r.team, r.count, r.complete])).toEqual([
      [1111, 5, true],
      [2222, 1, false],
      [3333, 0, false],
    ]);
    expect(rows[0]?.starter).toBe("Scout A");
    expect(rows[2]?.starter).toBeNull();
  });

  it("refuses a second record for the same watched match", () => {
    const saved = entry({
      id: "1",
      fieldValues: {
        watchedEvent: "2026TXHOU",
        matchType: "qual",
        matchNumber: "16",
      },
    });
    const values = {
      watchedEvent: " 2026txhou ",
      matchType: "qual",
      matchNumber: "16",
    };
    expect(isDuplicateRecord([saved], 1111, "2027test", values, "new")).toBe(
      true,
    );
    expect(isDuplicateRecord([saved], 1111, "2027test", values, "1")).toBe(
      false,
    );
    expect(
      isDuplicateRecord(
        [saved],
        1111,
        "2027test",
        { ...values, matchNumber: "17" },
        "new",
      ),
    ).toBe(false);
    expect(isDuplicateRecord([saved], 2222, "2027test", values, "new")).toBe(
      false,
    );
  });

  it("opens a record saved with one typed label as type plus number", () => {
    expect(splitLegacyLabel({ matchNumber: "Q16" })).toEqual({
      matchType: "qual",
      matchNumber: "16",
    });
    expect(splitLegacyLabel({ matchNumber: "playoff 7" })).toEqual({
      matchType: "playoff",
      matchNumber: "7",
    });
    const typed = { matchType: "final", matchNumber: "Q16" };
    expect(splitLegacyLabel(typed)).toBe(typed);
    expect(splitLegacyLabel({ matchNumber: "12" })).toEqual({
      matchNumber: "12",
    });
  });
});
