import { describe, expect, it } from "vitest";
import { alertLine, alertsHeading, parseAlert } from "./alerts";
import { parseConfig } from "./config";

const config = parseConfig({
  sections: [
    { name: "A", fields: [{ code: "climb", title: "Climb", type: "boolean" }] },
  ],
});

describe("parseAlert", () => {
  it("reads what the accuracy job writes, with the doc id as the entry", () => {
    expect(
      parseAlert("entry-1", {
        teamNumber: 1111,
        tbaMatchKey: "2027test_qm12",
        authorUid: "u1",
        acknowledged: false,
        flaggedFields: [
          { fieldCode: "climb", scoutedValue: true, officialValue: false },
          { fieldCode: "park" },
          { nope: 1 },
        ],
      }),
    ).toEqual({
      entryId: "entry-1",
      teamNumber: 1111,
      tbaMatchKey: "2027test_qm12",
      fieldCodes: ["climb", "park"],
    });
  });

  it("survives a document with the wrong types", () => {
    expect(
      parseAlert("e", { teamNumber: "x", flaggedFields: "no" }),
    ).toMatchObject({ teamNumber: 0, tbaMatchKey: "", fieldCodes: [] });
  });
});

describe("text", () => {
  it("says how many entries, singular and plural", () => {
    expect(alertsHeading(1)).toBe(
      "1 entry may have inaccurate data. Please review and re-scout if needed.",
    );
    expect(alertsHeading(3)).toContain("3 entries may have");
  });

  it("names the team, match and the form's field titles", () => {
    const line = alertLine(
      {
        entryId: "e",
        teamNumber: 1111,
        tbaMatchKey: "2027test_qm12",
        fieldCodes: ["climb", "park"],
      },
      config,
    );
    expect(line).toBe("Team 1111, Q12: Climb, park");
  });
});
