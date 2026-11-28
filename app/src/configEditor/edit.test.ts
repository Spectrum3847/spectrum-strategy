import { describe, expect, it } from "vitest";
import bundledPit from "../../../assets/pit_scout_config_default.json";
import { choiceEntries, type Doc, retiredKeys, sectionsOf } from "./doc";
import {
  activeChoiceDrafts,
  addQuestion,
  addSection,
  choiceKeyFor,
  codeFor,
  moveQuestion,
  removeQuestion,
  removeSection,
  reportDrawingOn,
  retiredChoiceDrafts,
  setReportDrawing,
  updateQuestion,
} from "./edit";
import { prepareSave } from "./revise";
import { checkConfigDoc } from "./validate";

const pit = bundledPit as Doc;
const section = (name: string) => {
  const index = sectionsOf(pit).findIndex((s) => s.name === name);
  return { index, fields: sectionsOf(pit)[index]?.fields as Doc[] };
};
const drivetrain = section("Drivetrain");
const driveIndex = drivetrain.fields.findIndex(
  (f) => f.code === "drivetrainType",
);
const fieldsAt = (doc: Doc, si: number) => sectionsOf(doc)[si]?.fields as Doc[];

describe("questions", () => {
  it("adds a question to the end of its section with a camelCase code", () => {
    const doc = addQuestion(pit, drivetrain.index, {
      title: "Bumper Color",
      description: " ",
      required: false,
      type: "text",
    });
    const last = fieldsAt(doc, drivetrain.index).at(-1);
    expect(last?.title).toBe("Bumper Color");
    expect(last?.code).toBe("bumperColor");
    expect("description" in (last ?? {})).toBe(false);
  });

  it("keeps a new code unique across the config", () => {
    expect(codeFor("Drive train type", pit)).toBe("driveTrainType");
    expect(codeFor("Email", pit)).toBe("email2");
    expect(codeFor("!!!", pit)).toBe("question");
  });

  it("adds a document question that defaults to nothing attached", () => {
    const doc = addQuestion(pit, 0, {
      title: "Field map 2",
      description: "",
      required: false,
      type: "document",
    });
    const added = fieldsAt(doc, 0).at(-1);
    expect(added?.type).toBe("document");
    expect(checkConfigDoc(doc).ok).toBe(true);
  });

  it("ignores an empty title", () => {
    expect(
      addQuestion(pit, 0, {
        title: "  ",
        description: "",
        required: false,
        type: "text",
      }),
    ).toBe(pit);
  });

  it("edits a title and keeps the code and type", () => {
    const doc = updateQuestion(pit, 0, 0, {
      title: "New Title",
      description: "",
      required: true,
    });
    const first = fieldsAt(doc, 0)[0];
    expect(first?.title).toBe("New Title");
    expect(first?.code).toBe(fieldsAt(pit, 0)[0]?.code);
    expect(first?.type).toBe(fieldsAt(pit, 0)[0]?.type);
    expect(first?.required).toBe(true);
  });

  it("keeps the old title when the new one is blank", () => {
    const doc = updateQuestion(pit, 0, 0, { title: " ", description: "" });
    expect(fieldsAt(doc, 0)[0]?.title).toBe(fieldsAt(pit, 0)[0]?.title);
  });

  it("removes a question", () => {
    const doc = removeQuestion(pit, 0, 0);
    expect(fieldsAt(doc, 0)).toHaveLength(fieldsAt(pit, 0).length - 1);
  });

  it("moves a question within its section", () => {
    const [a, b] = fieldsAt(pit, 0);
    const doc = moveQuestion(pit, 0, 0, 1);
    expect(fieldsAt(doc, 0).slice(0, 2)).toEqual([b, a]);
    expect(moveQuestion(pit, 0, 0, -1)).toEqual(pit);
  });
});

describe("sections", () => {
  it("adds an empty section at the end", () => {
    const doc = addSection(pit, " Pit extras ");
    expect(sectionsOf(doc)).toHaveLength(sectionsOf(pit).length + 1);
    expect(sectionsOf(doc).at(-1)).toEqual({ name: "Pit extras", fields: [] });
  });

  it("refuses to delete a section that still has questions", () => {
    expect(removeSection(pit, 0)).toBe(pit);
  });

  it("deletes an empty section", () => {
    const withEmpty = addSection(pit, "Temp");
    const last = sectionsOf(withEmpty).length - 1;
    expect(sectionsOf(removeSection(withEmpty, last))).toHaveLength(
      sectionsOf(pit).length,
    );
  });
});

describe("choices", () => {
  const edit = (choices: { key: string; label: string }[], doc = pit) =>
    updateQuestion(doc, drivetrain.index, driveIndex, {
      title: "Drive train",
      description: "",
      choices,
    });
  const drive = (doc: Doc) => fieldsAt(doc, drivetrain.index)[driveIndex] ?? {};

  it("starts from the active choices", () => {
    expect(activeChoiceDrafts(drive(pit)).map((c) => c.label)).toEqual([
      "Tank",
      "Swerve",
      "Other",
    ]);
  });

  it("adds a choice with a key derived from its label", () => {
    const next = [
      ...activeChoiceDrafts(drive(pit)),
      { key: choiceKeyFor("Custom", ["tank"]), label: "Custom" },
    ];
    expect(choiceEntries(drive(edit(next)).choices)?.at(-1)).toEqual([
      "custom",
      "Custom",
    ]);
  });

  it("retires a removed choice and keeps its label", () => {
    const [, ...rest] = activeChoiceDrafts(drive(pit));
    const field = drive(edit(rest));
    expect(retiredKeys(field)).toEqual(["tank"]);
    expect(choiceEntries(field.choices)).toEqual([
      ["swerve", "Swerve"],
      ["other", "Other"],
      ["tank", "Tank"],
    ]);
    expect(activeChoiceDrafts(field).map((c) => c.key)).toEqual([
      "swerve",
      "other",
    ]);
    expect(retiredChoiceDrafts(field).map((c) => c.label)).toEqual(["Tank"]);
  });

  it("restores a retired choice", () => {
    const [, ...rest] = activeChoiceDrafts(drive(pit));
    const retired = edit(rest);
    const back = edit(
      [...activeChoiceDrafts(drive(retired)), { key: "tank", label: "Tank" }],
      retired,
    );
    expect(retiredKeys(drive(back))).toEqual([]);
    expect("retiredChoiceKeys" in drive(back)).toBe(false);
  });

  it("renames a label and keeps the key", () => {
    const renamed = activeChoiceDrafts(drive(pit)).map((c) =>
      c.key === "tank" ? { ...c, label: "Tank Drive" } : c,
    );
    expect(choiceEntries(drive(edit(renamed)).choices)?.[0]).toEqual([
      "tank",
      "Tank Drive",
    ]);
  });

  it("reorders choices", () => {
    const [a, b, c] = activeChoiceDrafts(drive(pit));
    const order = edit([b, a, c].filter((x) => x !== undefined));
    expect(choiceEntries(drive(order).choices)?.[0]?.[0]).toBe("swerve");
  });

  it("never reuses a retired key for a new choice", () => {
    expect(choiceKeyFor("Tank", ["tank", "swerve"])).toBe("tank2");
  });

  it("produces a config that saves", () => {
    const [, ...rest] = activeChoiceDrafts(drive(pit));
    const doc = edit(rest);
    expect(checkConfigDoc(doc).ok).toBe(true);
    const saved = prepareSave(doc, pit, 6);
    expect(saved.ok).toBe(true);
  });
});

describe("report drawing", () => {
  it("is on unless the flag is false", () => {
    expect(reportDrawingOn({})).toBe(true);
    expect(reportDrawingOn(setReportDrawing({}, false))).toBe(false);
    expect(
      reportDrawingOn(setReportDrawing({ report_drawing: false }, true)),
    ).toBe(true);
  });
});
