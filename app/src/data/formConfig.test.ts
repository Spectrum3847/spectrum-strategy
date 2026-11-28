import { describe, expect, it } from "vitest";
import { allFields } from "../scout/config";
import { bundledConfig, replacesCached, resolveConfig } from "./formConfig";

const codes = (kind: "pit" | "prescout") =>
  allFields(bundledConfig[kind]).map((f) => f.code);

const copy = (revision: number, title = "Copy") =>
  JSON.stringify({ title, revision, sections: [] });

describe("bundled configs", () => {
  it("parses the pit form", () => {
    expect(bundledConfig.pit.title).toBe("Pit Scouting");
    expect(codes("pit")).toContain("drivetrainType");
    expect(codes("pit")).toContain("climbLevel");
  });

  it("parses the prescout form", () => {
    expect(bundledConfig.prescout.title).toBe("Pre-Scouting");
    expect(codes("prescout")).toEqual(
      expect.arrayContaining(["watchedEvent", "matchType", "matchNumber"]),
    );
  });
});

describe("resolveConfig", () => {
  const bundled = bundledConfig.pit;
  const rev = bundled.revision;

  it("takes a copy with a higher revision", () => {
    expect(resolveConfig(bundled, [copy(rev + 1)]).title).toBe("Copy");
  });

  it("keeps the bundled copy on a tie or a lower revision", () => {
    expect(resolveConfig(bundled, [copy(rev)]).title).toBe("Pit Scouting");
    expect(resolveConfig(bundled, [copy(0)]).title).toBe("Pit Scouting");
  });

  it("lets the highest of several copies win, in any order", () => {
    const low = copy(rev + 1, "Low");
    const high = copy(rev + 2, "High");
    expect(resolveConfig(bundled, [low, high]).title).toBe("High");
    expect(resolveConfig(bundled, [high, low]).title).toBe("High");
  });

  it("keeps the earlier copy on a tie", () => {
    expect(
      resolveConfig(bundled, [copy(rev + 1, "First"), copy(rev + 1, "Second")])
        .title,
    ).toBe("First");
  });

  it("skips a copy that is missing or does not parse", () => {
    expect(resolveConfig(bundled, [null, "{nope", ""]).title).toBe(
      "Pit Scouting",
    );
  });
});

describe("replacesCached", () => {
  it("caches into an empty cache", () => {
    expect(replacesCached(null, copy(1))).toBe(true);
  });

  it("caches a higher revision only", () => {
    expect(replacesCached(copy(2), copy(3))).toBe(true);
    expect(replacesCached(copy(2), copy(2))).toBe(false);
    expect(replacesCached(copy(2), copy(1))).toBe(false);
  });

  it("never caches a copy that does not parse", () => {
    expect(replacesCached(null, "{nope")).toBe(false);
    expect(replacesCached(copy(2), "{nope")).toBe(false);
  });

  it("replaces a cached copy that does not parse", () => {
    expect(replacesCached("{nope", copy(1))).toBe(true);
  });
});
