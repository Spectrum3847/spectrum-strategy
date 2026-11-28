import { readFileSync } from "node:fs";
import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { type Draft, limits, problemWith, reportDocument } from "./document";
import { traits } from "./traits";

const fixture = {
  id: "report-1",
  trait: "defense",
  teamNumber: 1234,
  matchNumber: 12,
  eventName: "Test Regional",
  eventKey: "2027test",
  report: "Pins robots",
  rating: 4,
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  updatedAt: "2027-03-05T18:04:05.123Z",
};

const now = new Date("2027-03-05T18:04:05.123Z");
const input = {
  id: "report-1",
  trait: "defense",
  team: 1234,
  match: 12,
  eventName: "Test Regional",
  eventKey: "2027test",
  report: "Pins robots",
  rating: 4,
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  now,
};

function rulesBody(fn: string): string {
  const rules = readFileSync(
    new URL("../../../firestore.rules", import.meta.url),
    "utf8",
  );
  const body = rules.slice(rules.indexOf(`function ${fn}(`));
  return body.slice(0, body.indexOf("\n    }\n"));
}

const quoted = (list: string) =>
  [...list.matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");

describe("reportDocument", () => {
  it("matches the stored report", () => {
    const doc = reportDocument(input);
    const { updatedAtTs, ...rest } = doc;
    expect(rest).toEqual(fixture);
    expect(Object.keys(doc)).not.toContain("strokes");
    expect(updatedAtTs).toBeInstanceOf(Timestamp);
    expect((updatedAtTs as Timestamp).toMillis()).toBe(now.getTime());
  });

  it("trims the text and limits the author name", () => {
    const doc = reportDocument({
      ...input,
      eventName: "  Test Regional ",
      report: "  Pins robots\n",
      authorDisplayName: "x".repeat(200),
    });
    expect(doc.eventName).toBe("Test Regional");
    expect(doc.report).toBe("Pins robots");
    expect(String(doc.authorDisplayName)).toHaveLength(limits.author);
  });

  it("writes only keys the rules allow, and all the required ones", () => {
    const body = rulesBody("isValidTrexTraitReport");
    const allowed = quoted(/hasOnly\(\[([^\]]*)\]\)/.exec(body)?.[1] ?? "");
    const keys = Object.keys(reportDocument(input));
    expect(allowed.length).toBeGreaterThan(0);
    for (const key of keys) expect(allowed).toContain(key);
    for (const key of allowed) {
      if (key !== "strokes") expect(keys).toContain(key);
    }
  });

  it("uses the trait keys the rules allow", () => {
    const body = rulesBody("isValidTrexTraitReport");
    const allowed = quoted(/data\.trait in \[([^\]]*)\]/.exec(body)?.[1] ?? "");
    expect(traits.map((t) => t.key).sort()).toEqual([...allowed].sort());
  });

  it("keeps the limits in step with the rules", () => {
    const body = rulesBody("isValidTrexTraitReport");
    const number = (pattern: RegExp) => Number(pattern.exec(body)?.[1]);
    expect(number(/teamNumber <= (\d+)/)).toBe(limits.team);
    expect(number(/matchNumber <= (\d+)/)).toBe(limits.match);
    expect(number(/eventName\.size\(\) <= (\d+)/)).toBe(limits.eventName);
    expect(number(/eventKey\.size\(\) <= (\d+)/)).toBe(limits.eventKey);
    expect(number(/report\.size\(\) <= (\d+)/)).toBe(limits.report);
    expect(number(/authorDisplayName\.size\(\) <= (\d+)/)).toBe(limits.author);
    expect(number(/rating >= (\d+)/)).toBe(limits.ratingMin);
    expect(number(/rating <= (\d+)/)).toBe(limits.ratingMax);
  });
});

describe("problemWith", () => {
  const ok: Draft = {
    trait: "defense",
    team: "1234",
    match: "12",
    eventName: "Test Regional",
    rating: 4,
    report: "Pins robots",
  };

  it("accepts a complete draft", () => {
    expect(problemWith(ok)).toBeNull();
    expect(problemWith({ ...ok, match: "0" })).toBeNull();
  });

  it.each([
    [{ trait: "speed" }, "Pick a trait."],
    [{ team: "" }, "Enter a team number."],
    [{ team: "0" }, "Enter a team number."],
    [{ team: "100000" }, "Enter a team number."],
    [{ match: "" }, "Enter a match number."],
    [{ match: "10000" }, "Enter a match number."],
    [{ eventName: "  " }, "Enter an event."],
    [{ rating: null }, "Pick a rating from 1 to 5."],
    [{ rating: 0 }, "Pick a rating from 1 to 5."],
    [{ rating: 6 }, "Pick a rating from 1 to 5."],
    [{ report: "  \n" }, "Enter a report."],
  ])("refuses %j", (patch, message) => {
    expect(problemWith({ ...ok, ...patch })).toBe(message);
  });

  it("refuses a report over the limit and says by how much", () => {
    expect(problemWith({ ...ok, report: "x".repeat(4100) })).toBe(
      "The report is 4 characters too long.",
    );
  });
});

describe("reportDocument drawing", () => {
  it("leaves strokes out when empty", () => {
    expect(reportDocument({ ...input, strokes: [] })).not.toHaveProperty(
      "strokes",
    );
  });

  it("carries the strokes list", () => {
    const strokes = [{ phase: "auton", colorValue: 1, points: [] }];
    expect(reportDocument({ ...input, strokes }).strokes).toEqual(strokes);
  });
});
