import { describe, expect, it } from "vitest";
import bundledPit from "../../../assets/pit_scout_config_default.json";
import { pickActive } from "./active";
import { choiceEntries, type Doc, retiredKeys } from "./doc";
import {
  describeChanges,
  hasChanges,
  maxConfigChars,
  nextRevision,
  prepareSave,
  reconcileChoices,
} from "./revise";

const drive = (choices: unknown, extra: Doc = {}): Doc => ({
  title: "Drive train",
  type: "select",
  required: true,
  code: "drivetrainType",
  formResetBehavior: "reset",
  choices,
  ...extra,
});

const config = (fields: Doc[], extra: Doc = {}): Doc => ({
  title: "Pit",
  delimiter: "\t",
  revision: 6,
  sections: [{ name: "Drivetrain", fields }],
  ...extra,
});

const fieldOf = (doc: Doc, code: string): Doc => {
  const sections = doc.sections as Doc[];
  const fields = sections.flatMap((s) => s.fields as Doc[]);
  const found = fields.find((f) => f.code === code);
  if (!found) throw new Error(`no field ${code}`);
  return found;
};

const live = config([
  drive({ tank: "Tank", swerve: "Swerve", other: "Other" }),
]);

describe("nextRevision", () => {
  it("goes above the active revision", () => {
    expect(nextRevision({ revision: 2 }, 6)).toBe(7);
    expect(nextRevision({}, 6)).toBe(7);
  });

  it("goes above an incoming revision that is already ahead", () => {
    expect(nextRevision({ revision: 12 }, 6)).toBe(13);
  });

  it("outranks the bundled default", () => {
    const bundledRevision = bundledPit.revision;
    expect(nextRevision({ revision: bundledRevision }, bundledRevision)).toBe(
      bundledRevision + 1,
    );
  });
});

describe("retiring removed choices", () => {
  it("keeps a dropped choice with its label and retires it", () => {
    const incoming = config([drive({ swerve: "Swerve", other: "Other" })]);
    const field = fieldOf(reconcileChoices(incoming, live), "drivetrainType");
    expect(choiceEntries(field.choices)).toEqual([
      ["swerve", "Swerve"],
      ["other", "Other"],
      ["tank", "Tank"],
    ]);
    expect(retiredKeys(field)).toEqual(["tank"]);
  });

  it("retires every choice but the one left, as the editor does", () => {
    const incoming = config([drive({ swerve: "Swerve" })]);
    const field = fieldOf(reconcileChoices(incoming, live), "drivetrainType");
    expect(retiredKeys(field)).toEqual(["tank", "other"]);
  });

  it("keeps an incoming retired list and does not retire anything extra", () => {
    const before = config([
      drive(
        { swerve: "Swerve", other: "Other", tank: "Tank" },
        { retiredChoiceKeys: ["tank"] },
      ),
    ]);
    const incoming = config([
      drive(
        { swerve: "Swerve", other: "Other", tank: "Tank" },
        { retiredChoiceKeys: ["tank"] },
      ),
    ]);
    const field = fieldOf(reconcileChoices(incoming, before), "drivetrainType");
    expect(retiredKeys(field)).toEqual(["tank"]);
  });

  it("brings back a retired choice a plain config lists again", () => {
    const before = config([
      drive(
        { swerve: "Swerve", tank: "Tank" },
        { retiredChoiceKeys: ["tank"] },
      ),
    ]);
    const incoming = config([drive({ tank: "Tank", swerve: "Swerve" })]);
    const field = fieldOf(reconcileChoices(incoming, before), "drivetrainType");
    expect(retiredKeys(field)).toEqual([]);
    expect("retiredChoiceKeys" in field).toBe(false);
  });

  it("keeps a choice that was already retired when the upload drops it", () => {
    const before = config([
      drive(
        { swerve: "Swerve", tank: "Tank" },
        { retiredChoiceKeys: ["tank"] },
      ),
    ]);
    const incoming = config([drive({ swerve: "Swerve" })]);
    const field = fieldOf(reconcileChoices(incoming, before), "drivetrainType");
    expect(choiceEntries(field.choices)).toEqual([
      ["swerve", "Swerve"],
      ["tank", "Tank"],
    ]);
    expect(retiredKeys(field)).toEqual(["tank"]);
  });

  it("reads the list form of choices", () => {
    const incoming = config([drive(["swerve", "other"])]);
    const field = fieldOf(reconcileChoices(incoming, live), "drivetrainType");
    expect(retiredKeys(field)).toEqual(["tank"]);
  });

  it("leaves a new field, or one with no live choices, alone", () => {
    const incoming = config([
      drive({ a: "A" }, { code: "newField" }),
      { title: "T", type: "text", code: "drivetrainType" },
    ]);
    expect(reconcileChoices(incoming, live)).toEqual(incoming);
  });

  it("changes nothing without a live copy", () => {
    const incoming = config([drive({ swerve: "Swerve" })]);
    expect(reconcileChoices(incoming, null)).toBe(incoming);
  });
});

describe("prepareSave", () => {
  it("stamps the revision, and the saved json carries it", () => {
    const result = prepareSave(live, live, 6);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.doc.revision).toBe(7);
    expect(JSON.parse(result.configJson).revision).toBe(7);
    expect(result.changes.revisionFrom).toBe(6);
    expect(result.changes.revisionTo).toBe(7);
  });

  it("goes above a live revision higher than the upload's", () => {
    const upload = config([drive({ swerve: "Swerve" })], { revision: 3 });
    const result = prepareSave(upload, live, 9);
    expect(result.ok && result.doc.revision).toBe(10);
  });

  it("writes a tab for an unusable delimiter", () => {
    const result = prepareSave({ ...live, delimiter: "" }, live, 6);
    expect(result.ok && result.doc.delimiter).toBe("\t");
  });

  it("keeps keys it does not read, such as the report drawing flag", () => {
    const result = prepareSave({ ...live, report_drawing: false }, live, 6);
    expect(result.ok && result.doc.report_drawing).toBe(false);
  });

  it("refuses a new choice that reuses a removed choice's label", () => {
    const incoming = config([drive({ t: "Tank", swerve: "Swerve" })]);
    const result = prepareSave(incoming, live, 6);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain("duplicate option values");
      expect(result.error).toContain("retired");
    }
  });

  it("refuses a config too large for one document", () => {
    const big = config([
      {
        title: "x".repeat(maxConfigChars),
        type: "text",
        code: "big",
      },
    ]);
    const result = prepareSave(big, live, 6);
    expect(result.ok).toBe(false);
  });
});

describe("describeChanges", () => {
  it("names added, removed and edited fields and sections", () => {
    const before = config([
      drive({ tank: "Tank" }),
      { title: "Old", type: "text", code: "old" },
    ]);
    const after: Doc = {
      ...before,
      title: "Pit v2",
      sections: [
        {
          name: "Drivetrain",
          fields: [
            drive({ tank: "Tank" }, { title: "Drive base" }),
            { title: "Weight", type: "number", code: "weight" },
          ],
        },
        { name: "Notes", fields: [] },
      ],
    };
    const changes = describeChanges(before, after, 6);
    expect(changes.fieldsAdded).toEqual(["Weight"]);
    expect(changes.fieldsRemoved).toEqual(["Old"]);
    expect(changes.fieldsEdited).toEqual(["Drive base"]);
    expect(changes.sectionsAdded).toEqual(["Notes"]);
    expect(changes.settings).toEqual(["Title"]);
  });

  it("names added, retired and restored choices", () => {
    const before = config([
      drive(
        { swerve: "Swerve", tank: "Tank", old: "Old" },
        { retiredChoiceKeys: ["old"] },
      ),
    ]);
    const after = config([
      drive(
        { swerve: "Swerve", tank: "Tank", old: "Old", mecanum: "Mecanum" },
        { retiredChoiceKeys: ["tank"] },
      ),
    ]);
    const changes = describeChanges(before, after, 6);
    expect(changes.choicesAdded).toEqual(["Drive train: Mecanum"]);
    expect(changes.choicesRetired).toEqual(["Drive train: Tank"]);
    expect(changes.choicesRestored).toEqual(["Drive train: Old"]);
  });

  it("calls a renamed choice label an edit", () => {
    const after = config([
      drive({ tank: "Tank drive", swerve: "Swerve", other: "Other" }),
    ]);
    expect(describeChanges(live, after, 6).fieldsEdited).toEqual([
      "Drive train",
    ]);
  });

  it("reports no changes for the same config", () => {
    expect(hasChanges(describeChanges(live, live, 6))).toBe(false);
  });
});

describe("pickActive", () => {
  const json = (revision: number, title: string) =>
    JSON.stringify({ title, revision, sections: [] });

  it("takes the highest revision and keeps the earlier on a tie", () => {
    const base = { title: "Bundled", revision: 4, sections: [] };
    expect(pickActive(base, [json(5, "Cached"), json(5, "Team")]).title).toBe(
      "Cached",
    );
    expect(pickActive(base, [json(5, "Cached"), json(8, "Team")]).title).toBe(
      "Team",
    );
    expect(pickActive(base, [json(4, "Tie")]).title).toBe("Bundled");
  });

  it("skips a copy that does not parse", () => {
    const base = { title: "Bundled", revision: 4, sections: [] };
    expect(pickActive(base, ["{ nope", null, "[]"]).title).toBe("Bundled");
  });
});
