import { describe, expect, it } from "vitest";
import type { TrexReport } from "../data/parse";
import { ratingsByTeam, ratingText, traitRatings } from "./ratings";

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

describe("traitRatings", () => {
  it("averages per trait in the fixed order and skips unrated reports", () => {
    const ratings = traitRatings([
      report({ trait: "fuelScoring", rating: 3 }),
      report({ trait: "defense", rating: 5 }),
      report({ trait: "defense", rating: 4 }),
      report({ trait: "defense", rating: null }),
      report({ trait: "autonomous", rating: null }),
      report({ trait: "mystery", rating: 2 }),
    ]);
    expect(ratings.map((r) => [r.key, r.average, r.count])).toEqual([
      ["defense", 4.5, 2],
      ["fuelScoring", 3, 1],
      ["mystery", 2, 1],
    ]);
    expect(ratings[0]?.label).toBe("Defense");
  });

  it("is empty when no report is rated", () => {
    expect(traitRatings([report({}), report({})])).toEqual([]);
  });
});

describe("ratingText", () => {
  it("says the average to one decimal and the count", () => {
    const base = { key: "defense", label: "Defense" };
    expect(ratingText({ ...base, average: 21 / 5, count: 5 })).toBe(
      "4.2 from 5 ratings",
    );
    expect(ratingText({ ...base, average: 4, count: 1 })).toBe(
      "4.0 from 1 rating",
    );
  });
});

describe("ratingsByTeam", () => {
  it("keeps each team's ratings apart", () => {
    const byTeam = ratingsByTeam([
      report({ teamNumber: 1111, rating: 5 }),
      report({ teamNumber: 2222, rating: 1 }),
      report({ teamNumber: 2222, rating: 2 }),
    ]);
    expect(byTeam.get(1111)?.[0]?.average).toBe(5);
    expect(byTeam.get(2222)?.[0]?.average).toBe(1.5);
  });
});
