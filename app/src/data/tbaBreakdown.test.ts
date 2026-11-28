import { describe, expect, it } from "vitest";
import { fetchAllianceCounts, parseAllianceCounts } from "./tbaBreakdown";

const path = ["hubScore", "totalCount"];

const played = {
  key: "2027test_qm1",
  alliances: {
    red: { team_keys: ["frc1111", "frc2222", "frc3333"], score: 50 },
    blue: { team_keys: ["frc4444", "frc5555", "frc6666"], score: 40 },
  },
  score_breakdown: {
    red: { hubScore: { totalCount: 31 } },
    blue: { hubScore: { totalCount: 24.9 } },
  },
};

describe("parseAllianceCounts", () => {
  it("reads the count at the path for each alliance", () => {
    expect(parseAllianceCounts([played], path)).toEqual([
      {
        matchKey: "2027test_qm1",
        alliance: "red",
        teams: [1111, 2222, 3333],
        count: 31,
      },
      {
        matchKey: "2027test_qm1",
        alliance: "blue",
        teams: [4444, 5555, 6666],
        count: 24,
      },
    ]);
  });

  it("reads climb and foul points, foul counts and a video when present", () => {
    const detailed = {
      ...played,
      videos: [
        { type: "tba", key: "x" },
        { type: "youtube", key: "abc123" },
      ],
      score_breakdown: {
        red: {
          hubScore: { totalCount: 31 },
          autoTowerPoints: 15,
          endGameTowerPoints: 30,
          foulPoints: 6,
          foulCount: 2,
          techFoulCount: 1,
        },
        blue: {
          hubScore: { totalCount: 24 },
          autoTowerPoints: 15,
          endGameTowerPoints: 30,
          totalTowerPoints: 45,
        },
      },
    };
    const [red, blue] = parseAllianceCounts([detailed], path);
    expect(red).toMatchObject({
      climbPoints: 45,
      foulPoints: 6,
      foulCount: 2,
      techFoulCount: 1,
      video: "abc123",
    });
    expect(blue?.climbPoints).toBe(45);
    expect(blue).not.toHaveProperty("foulPoints");
  });

  it("gives nothing for an unplayed match or another game's breakdown", () => {
    const unplayed = { ...played, key: "2027test_qm2", score_breakdown: null };
    const other = {
      ...played,
      key: "2027test_qm3",
      score_breakdown: { red: {} },
    };
    expect(parseAllianceCounts([unplayed, other], path)).toEqual([]);
  });

  it("ignores junk", () => {
    expect(parseAllianceCounts(null, path)).toEqual([]);
    expect(parseAllianceCounts([42, { key: 1 }], path)).toEqual([]);
  });
});

describe("fetchAllianceCounts", () => {
  it("asks for the full match list with the team key", async () => {
    let url = "";
    let auth = "";
    const fetcher = ((input: string, init: RequestInit) => {
      url = input;
      auth = (init.headers as Record<string, string>)["X-TBA-Auth-Key"] ?? "";
      return Promise.resolve(new Response(JSON.stringify([played])));
    }) as unknown as typeof fetch;
    const out = await fetchAllianceCounts("2027test", "k", path, fetcher);
    expect(url).toBe(
      "https://www.thebluealliance.com/api/v3/event/2027test/matches",
    );
    expect(auth).toBe("k");
    expect(out).toHaveLength(2);
  });
});
