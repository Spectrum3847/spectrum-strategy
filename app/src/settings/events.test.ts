import { describe, expect, it } from "vitest";
import {
  activeEventDoc,
  canSetTeamEvent,
  filterEvents,
  isEventNearby,
  parseEvents,
  seasonOf,
  weekLabel,
} from "./events";

const event = (over: Record<string, unknown>) => ({
  key: "2027aaa",
  name: "Alpha Regional",
  start_date: "2027-03-05",
  end_date: "2027-03-07",
  week: 0,
  event_type: 0,
  ...over,
});

describe("parseEvents", () => {
  it("keeps valid events in start order, undated last", () => {
    const events = parseEvents([
      event({ key: "2027ccc", name: "C", start_date: null, end_date: null }),
      event({ key: "2027bbb", name: "B", start_date: "2027-03-12" }),
      event({ key: "2027aaa", name: "A" }),
    ]);
    expect(events.map((e) => e.key)).toEqual(["2027aaa", "2027bbb", "2027ccc"]);
  });

  it("skips entries without a key or name and ignores non-arrays", () => {
    expect(
      parseEvents([event({ key: 5 }), event({ name: "" }), "x", null]),
    ).toEqual([]);
    expect(parseEvents({ key: "x" })).toEqual([]);
  });

  it("reads week and type as numbers or null", () => {
    const [e] = parseEvents([event({ week: null, event_type: "x" })]);
    expect(e?.week).toBeNull();
    expect(e?.eventType).toBeNull();
  });
});

describe("weekLabel", () => {
  const label = (over: Record<string, unknown>) => {
    const [e] = parseEvents([event(over)]);
    return e ? weekLabel(e) : "";
  };
  it("counts regular weeks from 1", () => {
    expect(label({ week: 0 })).toBe("Week 1");
    expect(label({ week: 5 })).toBe("Week 6");
  });
  it("names the events that have no week", () => {
    expect(label({ week: null, event_type: 4 })).toBe("Championship");
    expect(label({ week: null, event_type: 99 })).toBe("Offseason");
    expect(label({ week: null, event_type: 100 })).toBe("Preseason");
    expect(label({ week: null, event_type: 1 })).toBe("Other");
  });
});

describe("isEventNearby", () => {
  const now = new Date(2027, 2, 10, 15, 0);
  const span = (startDate: string | null, endDate: string | null) => ({
    startDate,
    endDate,
  });
  it("counts an event in progress", () => {
    expect(isEventNearby(span("2027-03-09", "2027-03-11"), now)).toBe(true);
  });
  it("counts one starting within three days, not four", () => {
    expect(isEventNearby(span("2027-03-13", "2027-03-15"), now)).toBe(true);
    expect(isEventNearby(span("2027-03-14", "2027-03-16"), now)).toBe(false);
  });
  it("counts one that ended within three days, not four", () => {
    expect(isEventNearby(span("2027-03-05", "2027-03-07"), now)).toBe(true);
    expect(isEventNearby(span("2027-03-04", "2027-03-06"), now)).toBe(false);
  });
  it("uses the start as the end when the end is missing", () => {
    expect(isEventNearby(span("2027-03-10", null), now)).toBe(true);
  });
  it("never counts an undated event", () => {
    expect(isEventNearby(span(null, null), now)).toBe(false);
    expect(isEventNearby(span("soon", "later"), now)).toBe(false);
  });
});

describe("filterEvents", () => {
  const now = new Date(2027, 2, 10);
  const events = parseEvents([
    event({ key: "2027near", name: "Near Regional", start_date: "2027-03-10" }),
    event({
      key: "2027far",
      name: "Far Regional",
      start_date: "2027-05-01",
      end_date: "2027-05-03",
    }),
  ]);
  const keys = (query: string, showAll: boolean) =>
    filterEvents(events, { query, showAll, now }).map((e) => e.key);

  it("lists nearby events by default", () => {
    expect(keys("", false)).toEqual(["2027near"]);
  });
  it("lists the whole season with Show all", () => {
    expect(keys("", true)).toEqual(["2027near", "2027far"]);
  });
  it("searches the whole season by name or key without Show all", () => {
    expect(keys("far reg", false)).toEqual(["2027far"]);
    expect(keys("2027FAR", false)).toEqual(["2027far"]);
  });
});

describe("team event", () => {
  it("is set by strategy, admin and developer only", () => {
    expect(canSetTeamEvent(["strategy"])).toBe(true);
    expect(canSetTeamEvent(["admin"])).toBe(true);
    expect(canSetTeamEvent(["developer"])).toBe(true);
    expect(canSetTeamEvent(["scouter"])).toBe(false);
    expect(canSetTeamEvent(["viewer"])).toBe(false);
  });
  it("writes the stored document shape", () => {
    expect(
      activeEventDoc("2027test", new Date("2027-03-05T18:00:00Z")),
    ).toEqual({
      eventKey: "2027test",
      updatedAt: "2027-03-05T18:00:00.000Z",
    });
  });
});

describe("seasonOf", () => {
  it("reads the year from an event key", () => {
    expect(seasonOf("2027test")).toBe(2027);
    expect(seasonOf("test")).toBeNull();
    expect(seasonOf("")).toBeNull();
  });
});
