import { describe, expect, it } from "vitest";
import { sectionFor, sections } from "./sections";

describe("sectionFor", () => {
  it("finds a section by id", () => {
    expect(sectionFor("event")?.title).toBe("Event");
  });

  it("returns null for no id or an unknown one, so Settings shows the list", () => {
    expect(sectionFor(null)).toBeNull();
    expect(sectionFor("nope")).toBeNull();
  });

  it("has unique ids", () => {
    expect(new Set(sections.map((s) => s.id)).size).toBe(sections.length);
  });
});
