import { readFileSync } from "node:fs";
import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import {
  applySections,
  emptyReport,
  isEmptyReport,
  maxSection,
  parseReport,
  reportDoc,
  reportId,
} from "./postMatch";

const root = (path: string) =>
  readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");

function ruleKeys(fn: string): string[] {
  const body = root("firestore.rules").slice(
    root("firestore.rules").indexOf(`function ${fn}(`),
  );
  const list = /hasOnly\(\[([^\]]*)\]\)/.exec(body)?.[1] ?? "";
  return [...list.matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");
}

const author = { uid: "u1", displayName: "Lead A" };
const stamp = Date.parse("2027-03-01T10:00:05.000Z");

const storedDoc = {
  id: "2027test_qm14",
  eventKey: "2027test",
  matchId: "qm14",
  auto: "Left start, scored two",
  teleop: "Defended 3333",
  endgame: "Climbed L2",
  notes: "Lost comms for ten seconds",
  authorUid: "u1",
  authorDisplayName: "Lead A",
  updatedAt: "2027-03-01T10:00:05.000Z",
  updatedAtTs: Timestamp.fromMillis(stamp),
};

const report = {
  ...emptyReport("2027test", "qm14"),
  auto: "Left start, scored two",
  teleop: "Defended 3333",
  endgame: "Climbed L2",
  notes: "Lost comms for ten seconds",
  authorUid: "u1",
  authorDisplayName: "Lead A",
  updatedMs: stamp,
};

describe("reportDoc", () => {
  it("writes the stored document", () => {
    expect(reportDoc(report)).toEqual(storedDoc);
  });

  it("has exactly the keys the rules allow", () => {
    expect(Object.keys(reportDoc(report)).sort()).toEqual(
      ruleKeys("isValidPostMatchReport").sort(),
    );
  });

  it("sends the text as typed", () => {
    const doc = reportDoc({ ...report, notes: "  spaced  \n" });
    expect(doc.notes).toBe("  spaced  \n");
  });

  it("round trips through parseReport", () => {
    expect(parseReport(report.id, reportDoc(report))).toEqual(report);
  });
});

describe("parseReport", () => {
  it("reads a stored document", () => {
    expect(parseReport("2027test_qm14", storedDoc)).toEqual(report);
  });

  it("treats a field of the wrong type as missing", () => {
    const read = parseReport("", {
      eventKey: "2027test",
      matchId: "qm1",
      auto: 4,
      notes: null,
      updatedAt: "not a date",
    });
    expect(read.id).toBe("2027test_qm1");
    expect(read.auto).toBe("");
    expect(read.notes).toBe("");
    expect(read.updatedMs).toBe(0);
  });

  it("falls back to updatedAt without a server timestamp", () => {
    const read = parseReport("a", { updatedAt: "2027-03-01T10:00:00.000Z" });
    expect(read.updatedMs).toBe(Date.parse("2027-03-01T10:00:00.000Z"));
  });
});

describe("applySections", () => {
  const prev = { ...report, updatedMs: 1_000_000 };
  const sections = { auto: "a", teleop: "t", endgame: "e", notes: "n" };

  it("replaces the four sections and the author", () => {
    const next = applySections(
      prev,
      sections,
      { uid: "u2", displayName: "Lead B" },
      2_000_000,
    );
    expect(next).toMatchObject({ ...sections, authorUid: "u2" });
    expect(next.authorDisplayName).toBe("Lead B");
    expect(next.updatedMs).toBe(2_000_000);
  });

  it("never stamps behind the revision it replaces", () => {
    expect(applySections(prev, sections, author, 500_000).updatedMs).toBe(
      1_000_000,
    );
  });

  it("caps the author name at the rules limit", () => {
    const next = applySections(
      prev,
      sections,
      { uid: "u1", displayName: "x".repeat(200) },
      2_000_000,
    );
    expect(next.authorDisplayName).toHaveLength(128);
  });
});

describe("rules limits", () => {
  it("matches the section bound", () => {
    const rules = root("firestore.rules");
    const body = rules.slice(rules.indexOf("function isValidPostMatchReport("));
    expect(body).toContain(`data.auto.size() <= ${maxSection}`);
    expect(body).toContain(`data.notes.size() <= ${maxSection}`);
  });

  it("keys a report by event and match", () => {
    expect(reportId("2027test", "qm14")).toBe("2027test_qm14");
  });

  it("is empty until a section has text", () => {
    expect(isEmptyReport(emptyReport("2027test", "qm1"))).toBe(true);
    expect(
      isEmptyReport({
        ...report,
        auto: "  ",
        teleop: "",
        endgame: "",
        notes: "",
      }),
    ).toBe(true);
    expect(
      isEmptyReport({
        ...report,
        auto: "",
        teleop: "",
        endgame: "",
        notes: "x",
      }),
    ).toBe(false);
  });
});
