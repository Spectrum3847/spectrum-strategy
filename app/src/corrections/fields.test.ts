import { describe, expect, it } from "vitest";
import { parseConfig } from "../scout/config";
import {
  changedFields,
  correctableFields,
  correctableGroups,
  visibleFields,
} from "./fields";
import { answerRows, entryLabel, newestFirst } from "./rows";

const config = parseConfig({
  title: "Test",
  revision: 1,
  sections: [
    {
      name: "Prematch",
      fields: [
        { title: "Match", code: "matchNumber", type: "TBA-match-number" },
        { title: "Team", code: "team", type: "TBA-team-and-robot" },
      ],
    },
    {
      name: "Teleop",
      fields: [
        { title: "Fuel", code: "fuel", type: "counter" },
        { title: "Defense", code: "defense", type: "boolean" },
        {
          title: "Cycles",
          code: "cycles",
          type: "action-tracker",
          actions: [
            { code: "shot", label: "Shot" },
            { code: "pass", label: "Pass" },
          ],
        },
        {
          title: "Defense note",
          code: "defNote",
          type: "text",
          visibleWhenCode: "defense",
          visibleWhenValue: "true",
        },
      ],
    },
    {
      name: "Endgame",
      fields: [
        {
          title: "Climb",
          code: "climb",
          type: "select",
          choices: { none: "None", l1: "Level 1" },
        },
      ],
    },
  ],
});

describe("correctable fields", () => {
  it("leaves out the match and team answers and groups by section", () => {
    const groups = correctableGroups(config);
    expect(groups.map((g) => g.name)).toEqual(["Teleop", "Endgame"]);
    expect(correctableFields(config).map((f) => f.code)).toEqual([
      "fuel",
      "defense",
      "cycles_shot_count",
      "cycles_pass_count",
      "defNote",
      "climb",
    ]);
  });

  it("turns each action tracker count into a counter", () => {
    const shot = correctableFields(config).find(
      (f) => f.code === "cycles_shot_count",
    );
    expect(shot).toMatchObject({ type: "counter", title: "Shot count" });
  });

  it("offers a conditional field only when its answer is given", () => {
    const fields = correctableFields(config);
    expect(visibleFields(fields, {}).map((f) => f.code)).not.toContain(
      "defNote",
    );
    expect(
      visibleFields(fields, { defense: true }).map((f) => f.code),
    ).toContain("defNote");
  });

  it("stores only values that differ from the scout's own", () => {
    const fields = correctableFields(config);
    expect(
      changedFields(
        fields,
        { fuel: 10, defense: false },
        { fuel: 14, defense: false, climb: "l1" },
      ),
    ).toEqual({ fuel: 14, climb: "l1" });
    expect(changedFields(fields, { fuel: 10 }, { fuel: 10 })).toEqual({});
    expect(changedFields(fields, { fuel: "10" }, { fuel: 10 })).toEqual({});
  });
});

describe("answer rows", () => {
  const fields = correctableFields(config);

  it("lists answered fields and marks corrected ones with the scout's answer", () => {
    const rows = answerRows(fields, {
      fieldValues: { fuel: 14, defense: false, climb: "l1" },
      rawValues: { fuel: 10, defense: false },
      corrected: ["fuel", "climb"],
    });
    expect(rows).toEqual([
      { code: "fuel", title: "Fuel", value: "14", was: "10" },
      { code: "defense", title: "Defense", value: "No", was: null },
      { code: "climb", title: "Climb", value: "Level 1", was: "" },
    ]);
  });

  it("keeps a field corrected to blank and hides one never answered", () => {
    const rows = answerRows(fields, {
      fieldValues: { defNote: "" },
      rawValues: { defNote: "Bad note" },
      corrected: ["defNote"],
    });
    expect(rows).toEqual([
      { code: "defNote", title: "Defense note", value: "", was: "Bad note" },
    ]);
  });
});

describe("entry order and label", () => {
  const e = (
    id: string,
    key: string | null,
    matchNumber: string,
    at: string,
  ) => ({
    id,
    tbaMatchKey: key,
    fieldValues: { matchNumber },
    updatedAt: at,
  });

  it("labels placed, typed and unplaced entries", () => {
    expect(entryLabel(e("a", "2027test_qm12", "", ""))).toBe("Q12");
    expect(entryLabel(e("b", null, "7", ""))).toBe("Match 7 (typed)");
    expect(entryLabel(e("c", null, "", ""))).toBe("Unplaced match");
  });

  it("puts the latest match first, then the newest save, then the unplaced", () => {
    const sorted = newestFirst([
      e("typed", null, "3", "2027-03-01T10:00:00Z"),
      e("q2", "2027test_qm2", "", "2027-03-01T10:00:00Z"),
      e("q10-old", "2027test_qm10", "", "2027-03-01T10:00:00Z"),
      e("q10-new", "2027test_qm10", "", "2027-03-01T11:00:00Z"),
    ]);
    expect(sorted.map((x) => x.id)).toEqual([
      "q10-new",
      "q10-old",
      "q2",
      "typed",
    ]);
  });
});
