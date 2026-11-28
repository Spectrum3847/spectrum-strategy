import { describe, expect, it } from "vitest";
import { canEditShifts, parseNames, resolveRoster } from "./roster";

describe("canEditShifts", () => {
  it("lets strategy, admin and developer edit, not scouters", () => {
    expect(canEditShifts(["strategy"])).toBe(true);
    expect(canEditShifts(["scouter", "admin"])).toBe(true);
    expect(canEditShifts(["developer"])).toBe(true);
    expect(canEditShifts(["scouter"])).toBe(false);
    expect(canEditShifts(["viewer"])).toBe(false);
    expect(canEditShifts([])).toBe(false);
  });
});

describe("parseNames", () => {
  it("splits on lines, commas, semicolons and tabs, and drops repeats", () => {
    expect(parseNames("Ada, grace;Linus\tAda\n\n  Ken  \r\nGRACE")).toEqual([
      "Ada",
      "grace",
      "Linus",
      "Ken",
    ]);
    expect(parseNames("  ,, ")).toEqual([]);
  });
});

describe("resolveRoster", () => {
  const profiles = [
    { uid: "u1", displayName: "Scout A" },
    { uid: "u2", displayName: "scout b" },
    { uid: "u3", displayName: "Twin" },
    { uid: "u4", displayName: "twin " },
    { uid: "u5", displayName: "" },
  ];

  it("links a name to the one account with that name, any case", () => {
    const r = resolveRoster(["SCOUT A", "Scout B"], profiles);
    expect(r.roster).toEqual([
      { uid: "u1", name: "SCOUT A" },
      { uid: "u2", name: "Scout B" },
    ]);
    expect(r.ambiguous).toEqual([]);
    expect(r.unmatched).toEqual([]);
  });

  it("gives no uid to a shared name or an unknown one, and says which", () => {
    const r = resolveRoster(["Twin", "Stranger"], profiles);
    expect(r.roster.map((e) => e.uid)).toEqual(["", ""]);
    expect(r.ambiguous).toEqual(["Twin"]);
    expect(r.unmatched).toEqual(["Stranger"]);
  });

  it("calls nothing unmatched when the profiles could not be loaded", () => {
    const r = resolveRoster(["Scout A"], null);
    expect(r.roster).toEqual([{ uid: "", name: "Scout A" }]);
    expect(r.unmatched).toEqual([]);
  });
});
