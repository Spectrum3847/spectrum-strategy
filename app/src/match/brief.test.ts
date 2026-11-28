import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import {
  applyEdit,
  briefDoc,
  briefId,
  emptyBrief,
  isEmptyBrief,
  matchIdOf,
  parseBrief,
} from "./brief";

const author = { uid: "u1", displayName: "Lead A" };

describe("ids", () => {
  it("keys a brief by event and match id", () => {
    expect(matchIdOf("2027test", "2027test_qm14")).toBe("qm14");
    expect(matchIdOf("2027test", "2027test_sf2m1")).toBe("sf2m1");
    expect(matchIdOf("2027test", "other_qm1")).toBe("other_qm1");
    expect(briefId("2027test", "qm14")).toBe("2027test_qm14");
  });
});

describe("parseBrief", () => {
  it("reads the stored document", () => {
    const brief = parseBrief("2027test_qm14", {
      id: "2027test_qm14",
      eventKey: "2027test",
      matchId: "qm14",
      robotPlans: { "1111": "Defend", "2222": "Score" },
      robotRoles: { "1111": { start: "Left", teleop: "Feed", extra: "x" } },
      keyPoints: "Watch 3333",
      ready: true,
      authorUid: "u1",
      authorDisplayName: "Lead A",
      updatedAt: "2027-03-01T10:00:00.000Z",
      updatedAtTs: Timestamp.fromMillis(Date.parse("2027-03-01T10:00:05Z")),
    });
    expect(brief.robotPlans).toEqual({ 1111: "Defend", 2222: "Score" });
    expect(brief.robotRoles).toEqual({
      1111: { start: "Left", teleop: "Feed" },
    });
    expect(brief.ready).toBe(true);
    expect(brief.updatedMs).toBe(Date.parse("2027-03-01T10:00:05Z"));
  });

  it("treats a field of the wrong type as missing", () => {
    const brief = parseBrief("id1", {
      robotPlans: { abc: "x", "1111": 5 },
      robotRoles: "no",
      keyPoints: 3,
      ready: "yes",
      updatedAt: "not a date",
    });
    expect(brief.id).toBe("id1");
    expect(brief.robotPlans).toEqual({});
    expect(brief.robotRoles).toEqual({});
    expect(brief.keyPoints).toBe("");
    expect(brief.ready).toBe(false);
    expect(brief.updatedMs).toBe(0);
  });

  it("falls back to updatedAt without a server timestamp", () => {
    const brief = parseBrief("a", { updatedAt: "2027-03-01T10:00:00.000Z" });
    expect(brief.updatedMs).toBe(Date.parse("2027-03-01T10:00:00.000Z"));
  });
});

describe("isEmptyBrief", () => {
  it("is empty until a plan, role or key point is written", () => {
    const base = emptyBrief("2027test", "qm1");
    expect(isEmptyBrief(base)).toBe(true);
    expect(isEmptyBrief({ ...base, robotPlans: { 1111: "  " } })).toBe(true);
    expect(isEmptyBrief({ ...base, robotPlans: { 1111: "Go" } })).toBe(false);
    expect(isEmptyBrief({ ...base, robotRoles: { 1111: { auto: "A" } } })).toBe(
      false,
    );
    expect(isEmptyBrief({ ...base, keyPoints: "k" })).toBe(false);
  });
});

describe("applyEdit", () => {
  const prev = {
    ...emptyBrief("2027test", "qm1"),
    robotPlans: { 1111: "Defend" },
    keyPoints: "keep",
    updatedMs: 1_000_000,
  };

  it("replaces the given parts and keeps the rest", () => {
    const next = applyEdit(prev, { ready: true }, author, 2_000_000);
    expect(next.ready).toBe(true);
    expect(next.robotPlans).toEqual({ 1111: "Defend" });
    expect(next.keyPoints).toBe("keep");
    expect(next.authorUid).toBe("u1");
    expect(next.updatedMs).toBe(2_000_000);
  });

  it("never stamps behind the revision it replaces", () => {
    const next = applyEdit(prev, { ready: true }, author, 500_000);
    expect(next.updatedMs).toBe(1_000_000);
  });

  it("caps the author name at the rules limit", () => {
    const next = applyEdit(
      prev,
      {},
      { uid: "u1", displayName: "x".repeat(200) },
      2_000_000,
    );
    expect(next.authorDisplayName).toHaveLength(128);
  });
});

describe("briefDoc", () => {
  const brief = {
    ...emptyBrief("2027test", "qm1"),
    robotPlans: { 1111: "Defend", 2222: "  " },
    robotRoles: {
      1111: { start: " Left ", auto: "" },
      2222: { start: "" },
    },
    ready: true,
    authorUid: "u1",
    authorDisplayName: "Lead A",
    updatedMs: Date.parse("2027-03-01T10:00:00.000Z"),
  };

  it("has exactly the keys the rules allow", () => {
    const doc = briefDoc(brief);
    expect(Object.keys(doc).sort()).toEqual(
      [
        "authorDisplayName",
        "authorUid",
        "eventKey",
        "id",
        "keyPoints",
        "matchId",
        "ready",
        "robotPlans",
        "robotRoles",
        "updatedAt",
        "updatedAtTs",
      ].sort(),
    );
  });

  it("matches the stored shape", () => {
    const doc = briefDoc(brief);
    expect(doc.id).toBe("2027test_qm1");
    expect(doc.robotPlans).toEqual({ "1111": "Defend" });
    expect(doc.robotRoles).toEqual({ "1111": { start: "Left" } });
    expect(doc.updatedAt).toBe("2027-03-01T10:00:00.000Z");
    expect(doc.updatedAtTs).toBeInstanceOf(Timestamp);
    expect((doc.updatedAtTs as Timestamp).toMillis()).toBe(brief.updatedMs);
  });

  it("leaves robotRoles out when nobody has a role", () => {
    const doc = briefDoc({ ...brief, robotRoles: { 1111: { start: "" } } });
    expect("robotRoles" in doc).toBe(false);
  });

  it("round trips through parseBrief", () => {
    const back = parseBrief(brief.id, briefDoc(brief));
    expect(back.robotPlans).toEqual({ 1111: "Defend" });
    expect(back.ready).toBe(true);
    expect(back.updatedMs).toBe(brief.updatedMs);
  });
});
