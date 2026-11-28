import { describe, expect, it } from "vitest";
import { allianceFit } from "./allianceFit";
import { noFacts } from "./facts";

describe("alliance fit", () => {
  it("counts only the best three and puts a no-gain line last", () => {
    const ours = [100, 90, 80].map((mean) => ({ ...noFacts, mean }));
    const lines = allianceFit(ours, { ...noFacts, mean: 50, defender: true });
    expect(lines).toEqual([
      "Plays defense: none of ours does",
      "No change to our best 3 (now 270)",
    ]);
    expect(allianceFit(ours, { ...noFacts, mean: 110 })[0]).toContain(
      "+30 pts",
    );
  });
  it("requires three attempts and two thirds success for reliable L3", () => {
    const result = allianceFit([], {
      ...noFacts,
      l3: { attempts: 3, successes: 2 },
    });
    expect(result[0]).toContain("Reliable L3");
    expect(
      allianceFit([], { ...noFacts, l3: { attempts: 2, successes: 2 } }),
    ).toEqual([]);
  });
});
