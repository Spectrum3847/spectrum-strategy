import { describe, expect, it } from "vitest";
import { parseConfig } from "./config";
import { decodeQrScout, encodeQrScout, payloadColumns } from "./qr";
import { entryValues, qrConfig, referencePayload } from "./qr.fixture";

describe("encodeQrScout", () => {
  it("matches the payload the Dart encoder produces", () => {
    expect(encodeQrScout(qrConfig, entryValues)).toBe(referencePayload);
  });

  it("gives an action tracker only its derived columns", () => {
    const codes = payloadColumns(qrConfig).map((c) => c.code);
    expect(codes).not.toContain("track");
    expect(codes.slice(8, 12)).toEqual([
      "track_a_count",
      "track_a_times",
      "track_b_count",
      "track_b_times",
    ]);
  });

  it("writes empty cells for missing values and 0 for a missing count", () => {
    const payload = encodeQrScout(qrConfig, {});
    expect(payload.split("\t")).toEqual([
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "0",
      "",
      "0",
      "",
      "",
    ]);
  });

  it("sends only the team of a team-and-robot value and joins a list", () => {
    const config = parseConfig({
      sections: [
        {
          name: "x",
          fields: [
            { code: "tr", type: "TBA-team-and-robot" },
            { code: "c", type: "checkbox-select" },
          ],
        },
      ],
    });
    expect(
      encodeQrScout(config, {
        tr: { teamNumber: 254, robotPosition: "R1" },
        c: ["a", " b ", ""],
      }),
    ).toBe("254\ta,b");
  });

  it("honors a custom delimiter and strips it from values", () => {
    const config = parseConfig({
      delimiter: "|",
      sections: [
        {
          name: "x",
          fields: [
            { code: "a", type: "text" },
            { code: "b", type: "text" },
          ],
        },
      ],
    });
    expect(encodeQrScout(config, { a: "x|y", b: "z" })).toBe("x y|z");
  });

  it("falls back to a tab for a delimiter outside 1 to 4 characters", () => {
    for (const delimiter of ["", "12345", 7]) {
      expect(parseConfig({ delimiter, sections: [] }).delimiter).toBe("\t");
    }
  });
});

describe("decodeQrScout", () => {
  it("reads the payload the Dart encoder produces", () => {
    const decoded = decodeQrScout(qrConfig, referencePayload);
    expect(decoded?.values).toEqual({
      scouter: "Sam",
      matchNumber: 12,
      robot: "R2",
      pTnumber: 1234,
      fuel: 7,
      level: 3.5,
      defense: true,
      traits: "a,b",
      track_a_count: 2,
      track_a_times: "1.5-2.5,8",
      track_b_count: 0,
      track_b_times: "",
      notes: "good auto ok",
    });
    expect([...(decoded?.doubles ?? [])]).toEqual(["level"]);
  });

  it("round trips what it encodes", () => {
    const payload = encodeQrScout(qrConfig, entryValues);
    const decoded = decodeQrScout(qrConfig, payload);
    expect(decoded && encodeQrScout(qrConfig, decoded.values)).toBe(payload);
  });

  it("parses a range as a double even when it reads as a whole number", () => {
    const decoded = decodeQrScout(
      qrConfig,
      referencePayload.replace("3.5", "3"),
    );
    expect(decoded?.values.level).toBe(3);
    expect(decoded?.doubles.has("level")).toBe(true);
    expect(decoded?.doubles.has("fuel")).toBe(false);
  });

  it("keeps a team number and drops the unknown station", () => {
    const config = parseConfig({
      sections: [
        { name: "x", fields: [{ code: "tr", type: "TBA-team-and-robot" }] },
      ],
    });
    expect(decodeQrScout(config, "254")?.values.tr).toEqual({
      teamNumber: 254,
      robotPosition: "",
    });
    expect(decodeQrScout(config, "x")?.values.tr).toBeNull();
  });

  it("accepts two columns more or fewer and refuses a bigger gap", () => {
    const cells = referencePayload.split("\t");
    expect(
      decodeQrScout(qrConfig, cells.slice(0, -2).join("\t")),
    ).not.toBeNull();
    expect(decodeQrScout(qrConfig, `${referencePayload}\t\t`)).not.toBeNull();
    expect(decodeQrScout(qrConfig, cells.slice(0, -3).join("\t"))).toBeNull();
    expect(decodeQrScout(qrConfig, "hello")).toBeNull();
  });

  it("fills tracker defaults when trailing cells were dropped", () => {
    const cells = referencePayload.split("\t").slice(0, 11);
    const decoded = decodeQrScout(qrConfig, cells.join("\t"));
    expect(decoded?.values.track_b_times).toBe("");
    expect(decoded?.values).not.toHaveProperty("notes");
  });

  it("returns null for a config with no columns", () => {
    expect(decodeQrScout(parseConfig({ sections: [] }), "a")).toBeNull();
  });
});
