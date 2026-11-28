import { describe, expect, it } from "vitest";
import { parseTeamNumber } from "./myTeam";
import { parseRank, recordText } from "./rankings";

const rankings = {
  rankings: [
    {
      rank: 1,
      team_key: "frc2222",
      matches_played: 5,
      record: { wins: 5, losses: 0, ties: 0 },
    },
    {
      rank: 2,
      team_key: "frc1111",
      matches_played: 5,
      record: { wins: 3, losses: 1, ties: 1 },
    },
  ],
};

describe("parseRank", () => {
  it("reads our rank, the field size and our record", () => {
    const rank = parseRank(rankings, 1111);
    expect(rank).toEqual({
      rank: 2,
      of: 2,
      wins: 3,
      losses: 1,
      ties: 1,
      played: 5,
    });
    expect(rank && recordText(rank)).toBe("3-1-1");
  });

  it("is null when the team, the list or the answer is missing", () => {
    expect(parseRank(rankings, 9999)).toBeNull();
    expect(parseRank({ rankings: [] }, 1111)).toBeNull();
    expect(parseRank(null, 1111)).toBeNull();
    expect(parseRank({ error: "bad" }, 1111)).toBeNull();
  });
});

describe("parseTeamNumber", () => {
  it("reads a plain or frc-prefixed number", () => {
    expect(parseTeamNumber("1111")).toBe(1111);
    expect(parseTeamNumber(" frc3847 ")).toBe(3847);
    expect(parseTeamNumber("99999")).toBe(99999);
  });

  it("rejects anything else", () => {
    for (const text of ["", "0", "12a", "-5", "100000", "1.5"]) {
      expect(parseTeamNumber(text), text).toBeNull();
    }
  });
});
