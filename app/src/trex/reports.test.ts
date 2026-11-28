import { describe, expect, it } from "vitest";
import type { TrexReport } from "../data/parse";
import { eventNameFor, groupReports, inEvent } from "./reports";

const report = (patch: Partial<TrexReport>): TrexReport => ({
  id: "r",
  trait: "defense",
  teamNumber: 1111,
  matchNumber: 1,
  eventName: "Test Regional",
  eventKey: "2027test",
  report: "Text",
  rating: null,
  scoutName: "Scout A",
  updatedAt: "2027-03-05T18:00:00.000Z",
  ...patch,
});

const none = {
  eventKey: "2027test",
  thisEventOnly: false,
  trait: "",
  search: "",
};

describe("inEvent", () => {
  it("counts a report with no key for any event", () => {
    expect(inEvent(report({ eventKey: "" }), "2027test")).toBe(true);
    expect(inEvent(report({ eventKey: "2026old" }), "2027test")).toBe(false);
    expect(inEvent(report({ eventKey: "2026old" }), "")).toBe(true);
  });
});

describe("eventNameFor", () => {
  it("reuses the name other reports use for the key", () => {
    expect(eventNameFor([report({})], "2027test")).toBe("Test Regional");
  });

  it("falls back to the key, and to nothing without one", () => {
    expect(eventNameFor([], "2027test")).toBe("2027test");
    expect(eventNameFor([report({ eventName: "" })], "2027test")).toBe(
      "2027test",
    );
    expect(eventNameFor([report({})], "")).toBe("");
  });
});

describe("groupReports", () => {
  const all = [
    report({ id: "a", teamNumber: 2222, trait: "fuelScoring" }),
    report({ id: "b", teamNumber: 1111, trait: "fuelScoring" }),
    report({
      id: "c",
      teamNumber: 1111,
      trait: "autonomous",
      updatedAt: "2027-03-05T17:00:00.000Z",
    }),
    report({
      id: "d",
      teamNumber: 1111,
      trait: "autonomous",
      updatedAt: "2027-03-05T19:00:00.000Z",
    }),
    report({ id: "e", teamNumber: 1111, trait: "newTrait" }),
    report({ id: "f", teamNumber: 3333, eventKey: "2026old" }),
  ];

  it("groups by team, then trait in the canonical order, newest first", () => {
    const groups = groupReports(all, none);
    expect(groups.map((g) => g.team)).toEqual([1111, 2222, 3333]);
    const first = groups[0];
    expect(first?.count).toBe(4);
    expect(first?.traits.map((t) => t.key)).toEqual([
      "autonomous",
      "fuelScoring",
      "newTrait",
    ]);
    expect(first?.traits[0]?.reports.map((r) => r.id)).toEqual(["d", "c"]);
    expect(first?.traits[2]?.label).toBe("newTrait");
  });

  it("filters by event, trait and team digits", () => {
    expect(
      groupReports(all, { ...none, thisEventOnly: true }).map((g) => g.team),
    ).toEqual([1111, 2222]);
    expect(
      groupReports(all, { ...none, trait: "fuelScoring" }).map((g) => g.team),
    ).toEqual([1111, 2222]);
    expect(
      groupReports(all, { ...none, search: "22" }).map((g) => g.team),
    ).toEqual([2222]);
    expect(groupReports(all, { ...none, search: "9" })).toEqual([]);
  });
});
