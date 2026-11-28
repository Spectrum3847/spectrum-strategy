import { describe, expect, it } from "vitest";
import type { PickList } from "../picks/pickList";
import { pickStatus } from "./pickStatus";

const list = (over: Partial<PickList> = {}): PickList => ({
  id: "l1",
  name: "Main list",
  teamNumbers: [],
  tiers: [],
  dnp: [],
  authorUid: "u1",
  authorDisplayName: "Lead A",
  updatedMs: 1,
  ...over,
});

describe("pickStatus", () => {
  it("names the tier and the place in the flattened list", () => {
    const l = list({
      teamNumbers: [1111, 2222, 3333],
      tiers: [
        { name: "1st pick", teams: [1111] },
        { name: "2nd pick", teams: [2222, 3333] },
      ],
    });
    expect(pickStatus(l, 3333)).toBe("Tier 2 (2nd pick), #3 on Main list");
    expect(pickStatus(l, 1111)).toBe("Tier 1 (1st pick), #1 on Main list");
  });

  it("states a do-not-pick reason", () => {
    const l = list({ dnp: [{ team: 4444, reason: "Tips over" }] });
    expect(pickStatus(l, 4444)).toBe("Do not pick: Tips over (Main list)");
  });

  it("says when the team is on neither", () => {
    expect(pickStatus(list(), 5555)).toBe("Not on Main list");
  });
});
