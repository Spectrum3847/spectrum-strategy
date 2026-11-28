import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { conflictMessage, startConflicts, usualStarts } from "./startConflicts";

const config = parseConfig(bundled);

const entry = (team: number, n: number, starting: unknown): EventEntry => ({
  id: `${team}-${n}`,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: `2027test_qm${n}`,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: { starting },
});

describe("usualStarts", () => {
  it("needs two entries and a position over half of them", () => {
    const usual = usualStarts(
      config,
      [
        entry(1111, 1, "Center Hub"),
        entry(1111, 2, "Center Hub"),
        entry(1111, 3, "Depot Bump"),
        entry(2222, 1, "Center Hub"),
        entry(3333, 1, "Center Hub"),
        entry(3333, 2, "Depot Bump"),
        entry(4444, 1, "No Show"),
        entry(4444, 2, "No Show"),
      ],
      [1111, 2222, 3333, 4444],
    );
    expect(usual.get(1111)).toEqual({
      team: 1111,
      position: "Center Hub",
      count: 2,
      total: 3,
    });
    expect(usual.has(2222)).toBe(false);
    expect(usual.has(3333)).toBe(false);
    expect(usual.has(4444)).toBe(false);
  });

  it("ignores teams outside the match", () => {
    const usual = usualStarts(
      config,
      [entry(9999, 1, "Center Hub"), entry(9999, 2, "Center Hub")],
      [1111],
    );
    expect(usual.size).toBe(0);
  });
});

describe("startConflicts", () => {
  const usual = usualStarts(
    config,
    [
      entry(1111, 1, "Center Hub"),
      entry(1111, 2, "Center Hub"),
      entry(2222, 1, "Center Hub"),
      entry(2222, 2, "Center Hub"),
      entry(2222, 3, "Center Hub"),
      entry(3333, 1, "Depot Bump"),
      entry(3333, 2, "Depot Bump"),
    ],
    [1111, 2222, 3333],
  );

  it("finds alliance mates on the same spot", () => {
    const found = startConflicts([1111, 2222, 3333], usual);
    expect(found).toHaveLength(1);
    expect(conflictMessage(found[0] ?? { position: "", starts: [] })).toBe(
      "1111 and 2222 both usually start Center Hub (2/2, 3/3)",
    );
  });

  it("finds none for different spots", () => {
    expect(startConflicts([1111, 3333], usual)).toEqual([]);
  });
});
