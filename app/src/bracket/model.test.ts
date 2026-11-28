import { describe, expect, it } from "vitest";
import { model, seeded } from "./model";

describe("playoff model", () => {
  const teams = Array.from({ length: 8 }, (_, i) => [
    i * 3 + 1,
    i * 3 + 2,
    i * 3 + 3,
  ]);
  const stats = new Map(
    teams.flat().map((t) => [t, { score: 100, sigma: 20 }]),
  );
  it("uses the best three and models a best of three finals", () => {
    const extra = [...(teams[0] ?? []), 99];
    const m = model(
      [extra, ...teams.slice(1)],
      new Map([...stats, [99, { score: 200, sigma: 20 }]]),
    );
    expect(m.scores[0]).toBe(400);
    const p = m.chance(1, 2);
    expect(m.chance(1, 2, true)).toBeCloseTo(p * p * (3 - 2 * p));
    expect(m.chance(1, 2) + m.chance(2, 1)).toBeCloseTo(1);
  });
  it("follows the double elimination feeds and stops at the slider", () => {
    const m = model(teams, stats),
      full = m.run();
    expect(full.played[4]?.aSeed).toBe(8);
    expect(full.played[8]?.bSeed).toBe(full.played[5]?.winner);
    expect(full.played[13]?.aSeed).toBe(full.played[10]?.winner);
    expect(m.run(3).played[3]?.winner).toBe(0);
    expect(m.run(14, seeded(4))).toEqual(m.run(14, seeded(4)));
  });
  it("counts a champion and two finalists per seeded run", () => {
    const m = model(teams, stats),
      odds = m.odds(5000, 10);
    expect(odds).toEqual(m.odds(5000, 10));
    expect(odds.title.reduce((a, b) => a + b, 0)).toBeCloseTo(1);
    expect(odds.finals.reduce((a, b) => a + b, 0)).toBeCloseTo(2);
  });
});
