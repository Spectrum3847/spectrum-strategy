import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { compareFacts } from "./compareFacts";

const config = parseConfig(bundled);

const entry = (
  id: string,
  team: number,
  match: number,
  values: Record<string, unknown>,
): EventEntry => ({
  id,
  tbaMatchKey: `2027test_qm${match}`,
  teamNumber: team,
  alliance: "Red",
  scoutName: "Scout A",
  updatedAt: "2027-03-01T12:00:00.000Z",
  fieldValues: { autoFuelScored: 4, teleopFuelScored: 10, ...values },
});

describe("compareFacts", () => {
  const entries = [
    entry("a", 1111, 1, { eLow: "Successful", comments: "Fast" }),
    entry("b", 1111, 2, { eLow: "Failed", ryCard: "Yellow", dieCard: true }),
    entry("c", 1111, 3, { eLow: "N/A" }),
    entry("d", 2222, 1, {}),
  ];

  it("counts climbs, cards and deaths for the team only", () => {
    const { scouted, facts } = compareFacts(config, entries, 1111);
    expect(scouted).toBe(3);
    expect(facts.climbSuccessRate).toBe(0.5);
    expect(facts.cards).toBe(1);
    expect(facts.disconnects).toBe(1);
    expect(facts.teleopIqm).toBe(10);
    expect(facts.autoIqm).toBe(4);
    expect(facts.comments).toEqual(["Fast"]);
  });

  it("has no climb rate when none was tried", () => {
    expect(
      compareFacts(config, entries, 2222).facts.climbSuccessRate,
    ).toBeNull();
  });

  it("reports an unscouted team as zero entries", () => {
    expect(compareFacts(config, entries, 9999).scouted).toBe(0);
  });
});
