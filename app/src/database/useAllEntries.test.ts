import { describe, expect, it } from "vitest";
import { seasonOf } from "./useAllEntries";

describe("seasonOf", () => {
  it("reads the year an event key starts with", () => {
    expect(seasonOf("2027test")).toBe("2027");
    expect(seasonOf("")).toBeNull();
    expect(seasonOf("test2027")).toBeNull();
  });
});
