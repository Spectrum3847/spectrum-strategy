import { describe, expect, it } from "vitest";
import {
  mappingRows,
  mappingText,
  parseMappingText,
  readMapping,
  starterMapping,
} from "./mapping";

describe("parseMappingText", () => {
  it("accepts the starter document", () => {
    const parsed = parseMappingText(mappingText(starterMapping(2027)));
    expect(parsed).toEqual({ ok: true, doc: starterMapping(2027) });
  });

  it("refuses text that is not an object with a mappings array", () => {
    for (const text of ["{", "[]", "3", "null", '{"year":2027}']) {
      expect(parseMappingText(text).ok, text).toBe(false);
    }
    expect(parseMappingText('{"mappings":"x"}')).toEqual({
      ok: false,
      error: '"mappings" must be an array.',
    });
  });

  it("keeps every key it was given", () => {
    const text = JSON.stringify({
      year: 2027,
      mappings: [
        {
          scoutFieldCode: "autoFuelScored",
          statboticsPath: "result.breakdown.{alliance}.auto_points",
          type: "counter",
        },
      ],
      extra: true,
    });
    const parsed = parseMappingText(text);
    expect(parsed.ok && parsed.doc).toEqual(JSON.parse(text));
  });
});

describe("mappingRows", () => {
  it("shows the checker's defaults for absent keys", () => {
    const rows = Object.fromEntries(mappingRows({ mappings: [{}, {}] }));
    expect(rows.Year).toBe("none");
    expect(rows["Compared fields"]).toBe("2");
    expect(rows["Field tolerance %"]).toBe("50");
    expect(rows["Alert at wrong fraction"]).toBe("0.5");
    expect(rows["Egregious deviation %"]).toBe("200");
  });
});

describe("readMapping", () => {
  it("treats a missing or malformed document as none", () => {
    expect(readMapping(undefined)).toBeNull();
    expect(readMapping([])).toBeNull();
    expect(readMapping({ year: 2027 })).toBeNull();
    expect(readMapping({ mappings: [] })).toEqual({ mappings: [] });
  });
});
