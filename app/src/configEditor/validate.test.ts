import { describe, expect, it } from "vitest";
import bundledPit from "../../../assets/pit_scout_config_default.json";
import bundledPrescout from "../../../assets/prescout_config_default.json";
import bundledScout from "../../../assets/scout_config_default.json";
import type { Doc } from "./doc";
import {
  checkConfigDoc,
  checkConfigText,
  typeProblem,
  unsupportedTypes,
  validationError,
} from "./validate";

type Fields = Doc[];

const config = (fields: Fields, extra: Doc = {}): Doc => ({
  title: "Custom",
  page_title: "",
  delimiter: "\t",
  sections: [{ name: "Auto", fields }],
  ...extra,
});

const select = (choices: unknown, type = "select"): Doc => ({
  title: "Start",
  type,
  required: false,
  code: "start",
  formResetBehavior: "reset",
  choices,
});

const tracker = (mode?: string): Doc => ({
  title: "Actions",
  type: "action-tracker",
  code: "auto",
  formResetBehavior: "reset",
  ...(mode ? { mode } : {}),
  actions: [{ code: "fuel", label: "Fuel" }],
});

const field = (code: string, type: string): Doc => ({
  title: code,
  type,
  required: false,
  code,
  formResetBehavior: "reset",
});

const refusal = (value: unknown) => {
  const check = checkConfigDoc(value);
  return check.ok ? null : check.error;
};

describe("select options", () => {
  it("accepts a select with unique option values", () => {
    expect(refusal(config([select({ Left: "L", Right: "R" })]))).toBeNull();
  });

  it("refuses a select whose options share a value", () => {
    expect(refusal(config([select({ Left: "same", Right: "same" })]))).toBe(
      'Select field "start" has duplicate option values; each option must map to a unique value.',
    );
  });

  it("refuses repeated values in the list form and for a dropdown", () => {
    expect(refusal(config([select(["A", "A"])]))).toContain("duplicate");
    expect(refusal(config([select({ a: "x", b: "x" }, "dropdown")]))).toContain(
      "duplicate",
    );
  });

  it("does not check a multi-select", () => {
    expect(
      refusal(config([select({ a: "x", b: "x" }, "checkbox-select")])),
    ).toBeNull();
  });
});

describe("action tracker delimiter", () => {
  const check = (delimiter: unknown, mode?: string) =>
    refusal(config([tracker(mode)], { delimiter }));

  it("refuses a comma delimiter with a tracker", () => {
    expect(check(",", "tap")).toContain('uses "," as its delimiter');
  });

  it("refuses a dash only for hold mode, and a missing mode is hold", () => {
    expect(check("-", "hold")).toContain('uses "-" as its delimiter');
    expect(check("-")).toContain('uses "-" as its delimiter');
    expect(check("-", "tap")).toBeNull();
  });

  it("accepts a tab either way", () => {
    expect(check("\t", "hold")).toBeNull();
    expect(check("\t", "tap")).toBeNull();
  });

  it("never refuses a config with no tracker", () => {
    expect(refusal(config([field("a", "number")], { delimiter: "," }))).toBe(
      null,
    );
  });

  it("falls back to a tab for an empty or overlong delimiter", () => {
    expect(check("")).toBeNull();
    expect(check("not-a-delimiter")).toBeNull();
    expect(check(undefined)).toBeNull();
  });

  it("reports the same text through validationError", () => {
    expect(validationError(config([tracker()], { delimiter: "," }))).toContain(
      "drop the tracker",
    );
  });
});

describe("the shape of the file", () => {
  it("refuses JSON that is not an object", () => {
    expect(checkConfigText("[]")).toEqual({
      ok: false,
      error: "Config JSON must be an object.",
    });
  });

  it("refuses text that is not JSON", () => {
    const check = checkConfigText("{ nope");
    expect(check.ok).toBe(false);
    if (!check.ok) expect(check.error).toMatch(/^This is not valid JSON/);
  });

  it("refuses a config with no sections", () => {
    expect(refusal({ title: "Empty", delimiter: "\t", sections: [] })).toBe(
      "Config has no sections.",
    );
    expect(refusal({ title: "Empty" })).toBe("Config has no sections.");
    expect(refusal({ title: "Empty", sections: ["a", 3] })).toBe(
      "Config has no sections.",
    );
  });

  it("accepts a section with no fields", () => {
    expect(refusal(config([]))).toBeNull();
  });
});

describe("keys of the wrong type", () => {
  it("refuses keys of the wrong type", () => {
    expect(refusal(config([], { title: 5 }))).toBe(
      'Config: "title" must be text.',
    );
    expect(refusal(config([], { revision: "3" }))).toContain('"revision"');
    expect(refusal(config([], { delimiter: 9 }))).toContain('"delimiter"');
    expect(refusal(config([], { report_drawing: "no" }))).toContain(
      "true or false",
    );
    expect(refusal(config([{ ...field("a", "text"), required: "yes" }]))).toBe(
      'Section Auto, field a: "required" must be true or false.',
    );
    expect(refusal(config([{ ...field("a", "number"), min: "1" }]))).toContain(
      '"min" must be a number.',
    );
    expect(
      refusal(config([{ ...field("a", "select"), retiredChoiceKeys: "x" }])),
    ).toContain("a list");
    expect(
      refusal(
        config([{ ...tracker("tap"), actions: [{ code: 1, label: "Fuel" }] }]),
      ),
    ).toContain("action");
  });

  it("allows missing and null keys", () => {
    expect(
      typeProblem(config([{ ...field("a", "text"), description: null }])),
    ).toBeNull();
  });
});

describe("warnings that do not block", () => {
  it("names the types the app cannot render, once each", () => {
    const check = checkConfigDoc(
      config([
        field("a", "action-tracker"),
        field("sm", "TBA-match-number"),
        field("m", "multi-select"),
        field("t", "timer"),
        field("t2", "Timer"),
        field("i", "image"),
        field("n", "hologram"),
      ]),
    );
    expect(check.ok).toBe(true);
    if (!check.ok) return;
    expect(unsupportedTypes(check.doc)).toEqual({
      known: ["timer", "image"],
      unrecognised: ["hologram"],
    });
    expect(check.warnings.join(" ")).toContain("they become text boxes");
    expect(check.warnings.join(" ")).toContain("not recognised at all");
  });

  it("reports nothing for implemented types", () => {
    const check = checkConfigDoc(
      config([field("a", "action-tracker"), field("b", "TBA-team-and-robot")]),
    );
    expect(check.ok && check.warnings).toEqual([]);
  });

  it("warns about a repeated or missing field code", () => {
    const check = checkConfigDoc(
      config([field("a", "text"), field("a", "number"), field("", "text")]),
    );
    expect(check.ok).toBe(true);
    if (check.ok) {
      expect(check.warnings.join(" ")).toContain('"a" is used more than once');
      expect(check.warnings.join(" ")).toContain("no code");
    }
  });
});

describe("the bundled forms", () => {
  it.each([
    ["scout", bundledScout],
    ["pit", bundledPit],
    ["prescout", bundledPrescout],
  ])("accept the %s default", (_name, doc) => {
    expect(refusal(doc)).toBeNull();
  });
});
