import { describe, expect, it } from "vitest";
import {
  fetchHistory,
  parseAwards,
  parsePlacement,
  parseSeasons,
  parseTeamEvents,
} from "./history";

describe("Statbotics rows", () => {
  it("reads seasons newest first", () => {
    const rows = parseSeasons([
      { year: 2025, record: { wins: 3, losses: 5, ties: 0 }, epa: {} },
      {
        year: 2026,
        record: { wins: 20, losses: 8, ties: 1 },
        epa: {
          total_points: 55.2,
          unitless: 1650,
          norm: { mean: 1712 },
          breakdown: { auto_points: 11, teleop_points: 30, endgame_points: 14 },
          ranks: { total: { rank: 222, team_count: 3500 } },
        },
      },
      "junk",
    ]);
    expect(rows.map((r) => r.year)).toEqual([2026, 2025]);
    expect(rows[0]).toMatchObject({
      wins: 20,
      ties: 1,
      epaRank: 222,
      epaRankTeamCount: 3500,
      norm: 1712,
      autoPoints: 11,
    });
    expect(rows[1]?.epaRank).toBeNull();
  });

  it("reads team events with the qualification rank", () => {
    const rows = parseTeamEvents([
      {
        event: "2026b",
        event_name: "B",
        year: 2026,
        record: {
          total: { wins: 8, losses: 4, ties: 0 },
          qual: { rank: 5, num_teams: 40 },
        },
        epa: { total_points: 61 },
      },
      { event: "2026a", year: 2026 },
    ]);
    expect(rows.map((r) => r.event)).toEqual(["2026a", "2026b"]);
    expect(rows[1]).toMatchObject({ rank: 5, numTeams: 40, totalPoints: 61 });
    expect(rows[0]?.rank).toBeNull();
  });

  it("treats a bad body as no rows", () => {
    expect(parseSeasons({})).toEqual([]);
    expect(parseTeamEvents(null)).toEqual([]);
  });
});

describe("TBA rows", () => {
  it("drops individual awards and marks winner and finalist", () => {
    expect(
      parseAwards([
        {
          name: "Finalist",
          award_type: 2,
          event_key: "2026a",
          year: 2026,
          recipient_list: [{ team_key: "frc1111", awardee: null }],
        },
        {
          name: "Dean's List",
          award_type: 17,
          event_key: "2026a",
          year: 2026,
          recipient_list: [{ team_key: "frc1111", awardee: "Student A" }],
        },
        {
          name: "Quality",
          award_type: 9,
          event_key: "2026a",
          year: 2026,
          recipient_list: [],
        },
      ]),
    ).toEqual([
      {
        name: "Finalist",
        eventKey: "2026a",
        year: 2026,
        isWinOrFinalist: true,
      },
      {
        name: "Quality",
        eventKey: "2026a",
        year: 2026,
        isWinOrFinalist: false,
      },
    ]);
  });

  it("finds the pick position and playoff level", () => {
    const alliances = [
      { picks: ["frc1", "frc2", "frc3"] },
      { picks: ["frc4", "frc1111", "frc5"], status: { level: "sf" } },
    ];
    expect(parsePlacement(alliances, "2026a", 1111)).toEqual({
      eventKey: "2026a",
      allianceNumber: 2,
      pickIndex: 1,
      roundReached: "sf",
    });
    expect(parsePlacement(alliances, "2026a", 9999)).toBeNull();
    expect(parsePlacement(null, "2026a", 1111)).toBeNull();
  });
});

describe("fetchHistory", () => {
  const json = (body: unknown) =>
    Promise.resolve(new Response(JSON.stringify(body)));
  const fetcher = (async (input: string | URL | Request) => {
    const url = String(input);
    if (url.includes("/team_years")) {
      return json([
        { year: 2026, record: {}, epa: {} },
        { year: 2025, record: {}, epa: {} },
        { year: 2024, record: {}, epa: {} },
      ]);
    }
    if (url.includes("/team_events")) {
      const year = /year=(\d+)/.exec(url)?.[1];
      return json([{ event: `${year}a`, year: Number(year) }]);
    }
    if (url.includes("/awards/")) return json([]);
    return json([{ picks: ["frc1111"], status: { level: "f" } }]);
  }) as typeof fetch;

  it("reads two seasons and needs no key for Statbotics", async () => {
    const found = await fetchHistory(1111, null, fetcher);
    expect(found.seasons.map((s) => s.year)).toEqual([2026, 2025]);
    expect(found.events.map((e) => e.event)).toEqual(["2026a", "2025a"]);
    expect(found.awards).toEqual([]);
    expect(found.alliances).toEqual([]);
  });

  it("adds alliance picks with a TBA key", async () => {
    const found = await fetchHistory(1111, "key", fetcher);
    expect(found.alliances.map((a) => a.eventKey)).toEqual(["2026a", "2025a"]);
  });

  it("fails when Statbotics has no answer for the seasons", async () => {
    const down = (() =>
      Promise.resolve(new Response("", { status: 500 }))) as typeof fetch;
    await expect(fetchHistory(1111, null, down)).rejects.toThrow();
  });
});
