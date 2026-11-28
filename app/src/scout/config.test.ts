import { describe, expect, it } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import {
  allFields,
  choiceOptions,
  effectiveDefault,
  emptyRequiredFields,
  fieldTypeOf,
  isVisible,
  parseConfig,
  pickConfig,
  selectedKeys,
} from "./config";

const make = (revision: number) =>
  parseConfig({ title: "T", revision, sections: [] });

describe("parseConfig", () => {
  it("parses the bundled default with every section and field", () => {
    const config = parseConfig(bundled);
    expect(config.revision).toBe(bundled.revision);
    expect(config.sections.map((s) => s.name)).toEqual(
      bundled.sections.map((s) => s.name),
    );
    expect(allFields(config).map((f) => f.code)).toEqual(
      bundled.sections.flatMap((s) => s.fields.map((f) => f.code)),
    );
  });

  it("accepts the JSON string the Firestore doc stores", () => {
    expect(parseConfig(JSON.stringify(bundled)).revision).toBe(
      bundled.revision,
    );
  });

  it("maps type names, with unknown types as text", () => {
    expect(fieldTypeOf("TBA-match-number")).toBe("tbaMatchNumber");
    expect(fieldTypeOf("tba_team_and_robot")).toBe("tbaTeamAndRobot");
    expect(fieldTypeOf("long-text")).toBe("longText");
    expect(fieldTypeOf("multi-select")).toBe("checkboxSelect");
    expect(fieldTypeOf("dropdown")).toBe("select");
    expect(fieldTypeOf("timer")).toBe("text");
  });

  it("keeps choice order and reads list choices", () => {
    const config = parseConfig({
      sections: [
        {
          name: "A",
          fields: [
            { code: "a", type: "select", choices: { b: "Two", a: "One" } },
            { code: "b", type: "select", choices: ["x", "y"] },
          ],
        },
      ],
    });
    const [a, b] = allFields(config);
    expect(a?.choices).toEqual([
      ["b", "Two"],
      ["a", "One"],
    ]);
    expect(b?.choices).toEqual([
      ["x", "x"],
      ["y", "y"],
    ]);
  });
});

describe("revision choice", () => {
  it("takes the higher revision", () => {
    expect(pickConfig(make(4), make(5)).revision).toBe(5);
    expect(pickConfig(make(5), make(4)).revision).toBe(5);
  });

  it("keeps the active config on a tie", () => {
    const active = make(4);
    expect(pickConfig(active, make(4))).toBe(active);
  });
});

describe("defaults", () => {
  const config = parseConfig(bundled);
  const field = (code: string) => {
    const f = allFields(config).find((x) => x.code === code);
    if (!f) throw new Error(`no field ${code}`);
    return f;
  };

  it("uses the configured default, else the type's empty value", () => {
    expect(effectiveDefault(field("robot"))).toBe("R1");
    expect(effectiveDefault(field("autoFuelScored"))).toBe(0);
    expect(effectiveDefault(field("tRdefense"))).toBe(false);
    expect(effectiveDefault(field("scouter"))).toBe("");
    expect(effectiveDefault(field("eLow"))).toBe("N/A");
    expect(effectiveDefault(field("ryCard"))).toBe("None");
  });

  it("joins a checkbox-select default list into the stored string", () => {
    const f = parseConfig({
      sections: [
        {
          name: "A",
          fields: [
            {
              code: "c",
              type: "checkbox-select",
              choices: { a: "A", b: "B" },
              defaultValue: ["a", "b"],
            },
          ],
        },
      ],
    });
    expect(effectiveDefault(allFields(f)[0] as never)).toBe("a,b");
    expect(selectedKeys(" a, b ,")).toEqual(["a", "b"]);
  });

  it("never defaults a select to a retired choice", () => {
    const f = parseConfig({
      sections: [
        {
          name: "A",
          fields: [
            {
              code: "s",
              type: "select",
              choices: { old: "Old", now: "Now" },
              retiredChoiceKeys: ["old"],
            },
          ],
        },
      ],
    });
    const field = allFields(f)[0];
    if (!field) throw new Error("missing");
    expect(effectiveDefault(field)).toBe("now");
    expect(choiceOptions(field, []).map(([k]) => k)).toEqual(["now"]);
    expect(choiceOptions(field, ["old"]).map(([k]) => k)).toEqual([
      "old",
      "now",
    ]);
  });
});

describe("visibility and required", () => {
  const config = parseConfig({
    sections: [
      {
        name: "A",
        fields: [
          {
            code: "kind",
            type: "select",
            required: true,
            choices: { a: "A", other: "Other" },
            defaultValue: "",
          },
          {
            code: "detail",
            type: "text",
            required: true,
            visibleWhenCode: "kind",
            visibleWhenValue: "other",
          },
          { code: "n", type: "number", required: true, min: 1, max: 5 },
          { code: "ok", type: "boolean", required: true },
        ],
      },
    ],
  });
  const [kind, detail] = allFields(config);

  it("shows a field only when the other field holds the value", () => {
    if (!detail || !kind) throw new Error("missing");
    expect(isVisible(detail, { kind: "a" })).toBe(false);
    expect(isVisible(detail, { kind: "other" })).toBe(true);
    expect(isVisible(kind, {})).toBe(true);
  });

  it("lists visible required fields with no answer, in order", () => {
    const empty = emptyRequiredFields(config, {
      kind: "other",
      detail: " ",
      n: "9",
    });
    expect(empty.map((f) => f.code)).toEqual(["detail", "n"]);
  });

  it("skips hidden required fields and counts booleans as answered", () => {
    const empty = emptyRequiredFields(config, { kind: "a", n: "3" });
    expect(empty).toEqual([]);
  });

  it("reports nothing for a No Show robot", () => {
    const noShow = parseConfig({
      sections: [
        {
          name: "A",
          fields: [
            {
              code: "start",
              type: "select",
              choices: { "No Show": "No Show", x: "X" },
            },
            { code: "t", type: "text", required: true },
          ],
        },
      ],
    });
    expect(emptyRequiredFields(noShow, { start: "No Show", t: "" })).toEqual(
      [],
    );
    expect(emptyRequiredFields(noShow, { start: "x", t: "" })).toHaveLength(1);
  });
});

describe("report_drawing", () => {
  it("is on unless the config turns it off", () => {
    expect(parseConfig({ sections: [] }).reportDrawing).toBe(true);
    expect(
      parseConfig({ sections: [], report_drawing: false }).reportDrawing,
    ).toBe(false);
    expect(
      parseConfig({ sections: [], report_drawing: true }).reportDrawing,
    ).toBe(true);
  });
});
