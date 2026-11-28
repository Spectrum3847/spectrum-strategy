import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { noteId, parseTeamNote } from "./teamNotes";

describe("team notes", () => {
  it("keys a note by event and team", () => {
    expect(noteId("2027test", 1111)).toBe("2027test_1111");
  });

  it("reads the timestamp first and the ISO string as a fallback", () => {
    const withTs = parseTeamNote("2027test_1111", {
      eventKey: "2027test",
      teamNumber: 1111,
      text: "Fast",
      authorUid: "u1",
      authorDisplayName: "Lead A",
      updatedAt: "2027-03-01T10:00:00.000Z",
      updatedAtTs: Timestamp.fromMillis(Date.parse("2027-03-01T10:00:05Z")),
    });
    expect(withTs.updatedMs).toBe(Date.parse("2027-03-01T10:00:05Z"));
    const legacy = parseTeamNote("2027test_1111", {
      updatedAt: "2027-03-01T10:00:00.000Z",
      text: 5,
    });
    expect(legacy.updatedMs).toBe(Date.parse("2027-03-01T10:00:00Z"));
    expect(legacy.text).toBe("");
  });
});
