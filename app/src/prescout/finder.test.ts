import { describe, expect, it } from "vitest";
import { planMatches, type Source } from "./finder";

const NOW = new Date(2027, 2, 20, 12);

const event = (
  key: string,
  end: string,
  over: Record<string, unknown> = {},
) => ({
  key,
  name: key.slice(4).toUpperCase(),
  start_date: end,
  end_date: end,
  event_type: 0,
  ...over,
});

let t = 1000;
function match(
  level: string,
  set: number,
  number: number,
  over: Record<string, unknown> = {},
) {
  t += 100;
  return {
    key: `x_${level}${level === "qm" ? number : `${set}m${number}`}`,
    comp_level: level,
    set_number: set,
    match_number: number,
    alliances: { red: { score: 10 }, blue: { score: 8 } },
    actual_time: t,
    videos: [{ type: "youtube", key: `vid${level}${set}${number}` }],
    ...over,
  };
}

const qms = (n: number) =>
  Array.from({ length: n }, (_, i) => match("qm", 1, i + 1));
const sfs = (n: number) =>
  Array.from({ length: n }, (_, i) => match("sf", i + 1, 1));

function source(
  events: unknown[],
  byEvent: Record<string, unknown[]>,
): Source & { asked: string[] } {
  const asked: string[] = [];
  return {
    asked,
    teamEvents: async () => events,
    teamMatches: async (key) => {
      asked.push(key);
      return byEvent[key] ?? [];
    },
  };
}

describe("planMatches", () => {
  it("takes the last 3 quals and last 2 playoffs, oldest first", async () => {
    const s = source([event("2027aaa", "2027-03-01")], {
      "2027aaa": [...qms(6), ...sfs(4)],
    });
    const plan = await planMatches(1111, 2027, "2027cur", s, NOW);
    expect(plan.matches.map((m) => `${m.matchType}${m.number}`)).toEqual([
      "qual4",
      "qual5",
      "qual6",
      "playoff3",
      "playoff4",
    ]);
    expect(plan.note).toBeNull();
    expect(plan.matches[0]?.videoUrl).toBe(
      "https://www.youtube.com/watch?v=vidqm14",
    );
  });

  it("fills with quals when the team has no playoff video", async () => {
    const s = source([event("2027aaa", "2027-03-01")], { "2027aaa": qms(8) });
    const plan = await planMatches(1111, 2027, "2027cur", s, NOW);
    expect(plan.matches).toHaveLength(5);
    expect(plan.note).toContain("no playoff videos, so 5 quals instead");
  });

  it("fills from an earlier event and keeps the newest event first", async () => {
    const s = source(
      [event("2027old", "2027-02-01"), event("2027new", "2027-03-01")],
      { "2027new": qms(2), "2027old": [...qms(4), ...sfs(2)] },
    );
    const plan = await planMatches(1111, 2027, "2027cur", s, NOW);
    expect(s.asked).toEqual(["2027new", "2027old"]);
    expect(plan.matches.map((m) => m.eventKey)).toEqual([
      "2027new",
      "2027new",
      "2027old",
      "2027old",
      "2027old",
    ]);
    expect(plan.note).toContain("the rest from OLD");
  });

  it("skips the active event, preseason, future events and unplayed or unfilmed matches", async () => {
    const s = source(
      [
        event("2027cur", "2027-03-01"),
        event("2027pre", "2027-02-20", { event_type: 100 }),
        event("2027fut", "2027-04-01"),
        event("2027aaa", "2027-03-02"),
      ],
      {
        "2027aaa": [
          match("qm", 1, 1, {
            alliances: { red: { score: -1 }, blue: { score: -1 } },
          }),
          match("qm", 1, 2, { videos: [{ type: "tba", key: "x" }] }),
          match("qm", 1, 3, { videos: [{ type: "youtube", key: "" }] }),
          match("qm", 1, 4),
        ],
      },
    );
    const plan = await planMatches(1111, 2027, "2027cur", s, NOW);
    expect(s.asked).toEqual(["2027aaa"]);
    expect(plan.matches.map((m) => m.number)).toEqual(["4"]);
    expect(plan.note).toContain("only 1 of 5 matches have video");
  });

  it("names playoff matches by set and carries the video start offset", async () => {
    const s = source([event("2027aaa", "2027-03-01")], {
      "2027aaa": [
        match("sf", 7, 1, { videos: [{ type: "youtube", key: "abc?t=95" }] }),
        match("sf", 7, 2),
        match("f", 1, 2),
      ],
    });
    const plan = await planMatches(1111, 2027, "2027cur", s, NOW);
    const byNumber = Object.fromEntries(plan.matches.map((m) => [m.number, m]));
    expect(byNumber["7"]?.videoUrl).toBe(
      "https://www.youtube.com/watch?v=abc&t=95",
    );
    expect(byNumber["7-2"]?.matchType).toBe("playoff");
    expect(byNumber["2"]?.matchType).toBe("final");
  });

  it("says so when there are no events or no videos", async () => {
    const none = await planMatches(1111, 2027, "2027cur", source([], {}), NOW);
    expect(none.matches).toEqual([]);
    expect(none.note).toContain("no 2027 events");
    const bare = await planMatches(
      1111,
      2027,
      "2027cur",
      source([event("2027aaa", "2027-03-01")], {}),
      NOW,
    );
    expect(bare.note).toContain("no match videos for 1111");
  });

  it("stops after six events", async () => {
    const events = Array.from({ length: 8 }, (_, i) =>
      event(`2027e${i}`, `2027-02-0${i + 1}`),
    );
    const s = source(events, {});
    await planMatches(1111, 2027, "2027cur", s, NOW);
    expect(s.asked).toHaveLength(6);
  });
});
