import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { parseConfig } from "./config";
import { entryDocument, extractTeam, matchIdFor } from "./entry";

const config = parseConfig({
  title: "T",
  revision: 1,
  sections: [
    {
      name: "Pre",
      fields: [
        { code: "scouter", type: "text" },
        { code: "matchNumber", type: "TBA-match-number" },
        {
          code: "robot",
          type: "select",
          choices: { R2: "Red 2", B1: "Blue 1" },
        },
        { code: "pTnumber", type: "number" },
      ],
    },
    {
      name: "Auto",
      fields: [
        { code: "fuel", type: "counter", buttons: [1, 5] },
        { code: "defense", type: "boolean" },
        { code: "level", type: "scale" },
        {
          code: "traits",
          type: "checkbox-select",
          choices: { a: "A", b: "B" },
        },
      ],
    },
  ],
});

const documentFixture = {
  id: "entry-1",
  matchId: "2027test_qm12",
  teamNumber: 1234,
  alliance: "Red",
  notes: "",
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  updatedAt: "2027-03-05T18:04:05.123Z",
  createdAt: "2027-03-05T18:04:05.123Z",
  byPhase: {
    auton: { score: 0, penalties: 0, notes: "", counters: {} },
    teleop: { score: 0, penalties: 0, notes: "", counters: {} },
    endgame: { score: 0, penalties: 0, notes: "", counters: {} },
  },
  fieldValues: {
    scouter: "Sam",
    matchNumber: "12",
    robot: "R2",
    pTnumber: "1234",
    fuel: 7,
    defense: true,
    level: "x",
    traits: "a,b",
  },
  tbaMatchKey: "2027test_qm12",
};

const now = new Date("2027-03-05T18:04:05.123Z");
const values = {
  scouter: "Sam",
  matchNumber: 12,
  robot: "R2",
  pTnumber: 1234,
  fuel: "7",
  defense: true,
  level: "x",
  traits: "a,b",
};
const base = {
  id: "entry-1",
  config,
  values,
  matchId: "2027test_qm12",
  tbaMatchKey: "2027test_qm12",
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  now,
};

describe("entryDocument", () => {
  it("matches the stored entry document", () => {
    const doc = entryDocument(base);
    const { updatedAtTs, ...rest } = doc;
    expect(rest).toEqual(documentFixture);
    expect(Object.keys(doc).sort()).toEqual(
      [...Object.keys(documentFixture), "updatedAtTs"].sort(),
    );
    expect(updatedAtTs).toEqual(
      new Timestamp(Date.UTC(2027, 2, 5, 18, 4, 5) / 1000, 123_000_000),
    );
  });

  it("derives the alliance from a blue station", () => {
    const doc = entryDocument({ ...base, values: { ...values, robot: "B1" } });
    expect(doc.alliance).toBe("Blue");
  });

  it("omits tbaMatchKey and empty fieldValues like toJson does", () => {
    const empty = parseConfig({ sections: [] });
    const doc = entryDocument({
      ...base,
      config: empty,
      values: {},
      tbaMatchKey: null,
    });
    expect("tbaMatchKey" in doc).toBe(false);
    expect("fieldValues" in doc).toBe(false);
    expect(doc.teamNumber).toBe(0);
  });

  it("adds the credited scout, with a uid only when there is one", () => {
    const named = entryDocument({
      ...base,
      scoutedBy: { name: "Robin", uid: "uid-9" },
    });
    expect(named.scoutedByName).toBe("Robin");
    expect(named.scoutedByUid).toBe("uid-9");
    expect(named.authorUid).toBe("uid-1");
    const typed = entryDocument({
      ...base,
      scoutedBy: { name: "Kit", uid: "" },
    });
    expect(typed.scoutedByName).toBe("Kit");
    expect("scoutedByUid" in typed).toBe(false);
  });

  it("writes no credit fields without a name", () => {
    for (const scoutedBy of [undefined, { name: "  ", uid: "u" }]) {
      const doc = entryDocument({
        ...base,
        ...(scoutedBy ? { scoutedBy } : {}),
      });
      expect("scoutedByName" in doc).toBe(false);
      expect("scoutedByUid" in doc).toBe(false);
    }
  });

  it("bounds the credited name to the rules limit", () => {
    const doc = entryDocument({
      ...base,
      scoutedBy: { name: "x".repeat(300), uid: "u".repeat(300) },
    });
    expect(String(doc.scoutedByName)).toHaveLength(128);
    expect(String(doc.scoutedByUid)).toHaveLength(128);
  });

  it("keeps createdAt from the first save", () => {
    const doc = entryDocument({
      ...base,
      createdAt: "2027-03-05T17:00:00.000Z",
    });
    expect(doc.createdAt).toBe("2027-03-05T17:00:00.000Z");
    expect(doc.updatedAt).toBe("2027-03-05T18:04:05.123Z");
  });
});

describe("extractTeam", () => {
  it("prefers a team-and-robot value, then the usual codes", () => {
    const withPick = parseConfig({
      sections: [
        { name: "A", fields: [{ code: "pick", type: "TBA-team-and-robot" }] },
      ],
    });
    expect(
      extractTeam(withPick, {
        pick: { teamNumber: 77, robotPosition: "R1" },
        pTnumber: 5,
      }),
    ).toBe(77);
    expect(extractTeam(config, { pTnumber: "254" })).toBe(254);
    expect(extractTeam(config, { pTnumber: "0", team: 9 })).toBe(9);
    expect(extractTeam(config, {})).toBe(0);
  });
});

describe("matchIdFor", () => {
  it("is the TBA key when the schedule resolved one", () => {
    expect(matchIdFor("2027test_qm3", "2027test", "3")).toBe("2027test_qm3");
  });

  it("falls back to event and typed number, within the rules limit", () => {
    expect(matchIdFor(null, "2027test", " 3 ")).toBe("2027test_typed_3");
    expect(matchIdFor(null, "", "3")).toBe("unscheduled_typed_3");
    expect(matchIdFor(null, "e", "x".repeat(300))).toHaveLength(128);
  });
});

describe("entryDocument drawing", () => {
  it("leaves strokesByPhase out when there is no drawing", () => {
    expect(entryDocument({ ...base, strokesByPhase: null })).not.toHaveProperty(
      "strokesByPhase",
    );
  });

  it("carries the drawing as given", () => {
    const strokes = { auton: [{ phase: "auton", points: [] }] };
    expect(
      entryDocument({ ...base, strokesByPhase: strokes }).strokesByPhase,
    ).toEqual(strokes);
  });
});
