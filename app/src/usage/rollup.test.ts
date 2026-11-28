import { describe, expect, it } from "vitest";
import { busiestDay, freshness, isEmptyRollup, parseRollup } from "./rollup";

describe("parseRollup", () => {
  it("reads the cron's document", () => {
    const r = parseRollup({
      updatedAt: "2027-03-04T05:06:07.000Z",
      windowDays: 30,
      eventsCounted: 12,
      deviceCount: 3,
      tabs: [{ name: "Scout", count: 8 }],
      platforms: [{ name: "web", count: 12 }],
      appVersions: [{ name: "0.1.0", count: "12" }],
      daily: [{ date: "2027-03-04", count: 12.2 }],
    });
    expect(r.eventsCounted).toBe(12);
    expect(r.tabs).toEqual([{ name: "Scout", count: 8 }]);
    expect(r.appVersions[0]?.count).toBe(12);
    expect(r.daily).toEqual([{ date: "2027-03-04", count: 12 }]);
    expect(r.updatedAt?.toISOString()).toBe("2027-03-04T05:06:07.000Z");
    expect(isEmptyRollup(r)).toBe(false);
  });

  it("drops bad rows and tolerates a bare document", () => {
    const r = parseRollup({
      tabs: [{ name: "", count: 1 }, null, 4, { name: "Scout" }],
      daily: "nope",
      updatedAt: "not a date",
    });
    expect(r.tabs).toEqual([{ name: "Scout", count: 0 }]);
    expect(r.daily).toEqual([]);
    expect(r.updatedAt).toBeNull();
    expect(isEmptyRollup(r)).toBe(true);
    expect(freshness(r.updatedAt)).toBe("Last updated: unknown.");
  });

  it("finds the busiest day", () => {
    expect(busiestDay([])).toBe(0);
    expect(
      busiestDay([
        { date: "a", count: 2 },
        { date: "b", count: 9 },
      ]),
    ).toBe(9);
  });
});
