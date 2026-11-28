import { describe, expect, it } from "vitest";
import { parseConfig } from "../scout/config";
import { startValues } from "./config";
import { parseTeamParam } from "./kinds";

describe("startValues", () => {
  const config = parseConfig({
    sections: [
      {
        name: "S",
        fields: [
          { code: "a", type: "text", defaultValue: "x" },
          { code: "b", type: "boolean" },
          { code: "c", type: "counter" },
        ],
      },
    ],
  });

  it("starts from the defaults", () => {
    expect(startValues(config, null, null)).toEqual({ a: "x", b: false, c: 0 });
  });

  it("lets saved answers, then a draft, win", () => {
    expect(startValues(config, { a: "saved", b: true }, null)).toEqual({
      a: "saved",
      b: true,
      c: 0,
    });
    expect(startValues(config, { a: "saved" }, { a: "draft" }).a).toBe("draft");
  });

  it("keeps an answer to a question the form no longer asks", () => {
    expect(startValues(config, { gone: "kept" }, null).gone).toBe("kept");
  });
});

describe("parseTeamParam", () => {
  it("accepts a team number the rules accept", () => {
    expect(parseTeamParam("1234")).toBe(1234);
    expect(parseTeamParam("99999")).toBe(99999);
  });

  it("refuses anything else", () => {
    for (const bad of [undefined, "", "0", "abc", "100000", "-5", "12.5"]) {
      expect(parseTeamParam(bad)).toBeNull();
    }
  });
});
