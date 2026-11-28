import { readFileSync } from "node:fs";
import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import { parseConfig } from "../scout/config";
import { formEntryDocument } from "./document";

const pitConfig = parseConfig({
  title: "Pit",
  revision: 1,
  sections: [
    {
      name: "Drivetrain",
      fields: [
        {
          code: "drivetrainType",
          type: "select",
          choices: { swerve: "Swerve" },
        },
        { code: "swerveGearRatio", type: "text" },
        { code: "climbLevel", type: "checkbox-select", choices: { l1: "L1" } },
        { code: "trenchFit", type: "boolean" },
        { code: "comments", type: "long-text" },
        { code: "fieldMap", type: "document" },
      ],
    },
  ],
});

const prescoutConfig = parseConfig({
  title: "Prescout",
  revision: 1,
  sections: [
    {
      name: "Match",
      fields: [
        { code: "watchedEvent", type: "text" },
        { code: "matchType", type: "select", choices: { qual: "Qual" } },
        { code: "matchNumber", type: "text" },
        { code: "autoFuelScored", type: "counter" },
        { code: "climbSeconds", type: "number" },
      ],
    },
  ],
});

const now = new Date("2027-03-05T18:04:05.123Z");
const base = {
  id: "entry-1",
  team: 1234,
  eventKey: "2027test",
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  now,
};

const pitFixture = {
  id: "entry-1",
  teamNumber: 1234,
  eventKey: "2027test",
  fieldValues: {
    drivetrainType: "swerve",
    swerveGearRatio: "6.75",
    climbLevel: "l1",
    trenchFit: true,
    comments: "Fast intake",
    fieldMap: "",
  },
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  photoKeys: ["key-a"],
  updatedAt: "2027-03-05T18:04:05.123Z",
};

const prescoutFixture = {
  id: "entry-1",
  teamNumber: 1234,
  eventKey: "2027test",
  fieldValues: {
    watchedEvent: "2026txhou",
    matchType: "qual",
    matchNumber: "16",
    autoFuelScored: 7,
    climbSeconds: "0",
  },
  authorUid: "uid-1",
  authorDisplayName: "Sam Scout",
  updatedAt: "2027-03-05T18:04:05.123Z",
};

const stamp = new Timestamp(Date.UTC(2027, 2, 5, 18, 4, 5) / 1000, 123_000_000);

function ruleKeys(fn: string): string[] {
  const rules = readFileSync(
    new URL("../../../firestore.rules", import.meta.url),
    "utf8",
  );
  const body = rules.slice(rules.indexOf(`function ${fn}(`));
  const list = /hasOnly\(\[([^\]]*)\]\)/.exec(body)?.[1] ?? "";
  return [...list.matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");
}

describe("formEntryDocument", () => {
  it("matches the stored pit document", () => {
    const doc = formEntryDocument({
      ...base,
      kind: "pit",
      config: pitConfig,
      values: {
        drivetrainType: "swerve",
        swerveGearRatio: "6.75",
        climbLevel: "l1",
        trenchFit: true,
        comments: "Fast intake",
        fieldMap: "",
      },
      photoKeys: ["key-a"],
    });
    const { updatedAtTs, ...rest } = doc;
    expect(rest).toEqual(pitFixture);
    expect(updatedAtTs).toEqual(stamp);
    expect(Object.keys(doc).sort()).toEqual(
      [...Object.keys(pitFixture), "updatedAtTs"].sort(),
    );
  });

  it("keeps the event key on a pit entry, empty or not", () => {
    for (const eventKey of ["2027test", ""]) {
      const doc = formEntryDocument({
        ...base,
        eventKey,
        kind: "pit",
        config: pitConfig,
        values: {},
      });
      expect(doc.eventKey).toBe(eventKey);
    }
  });

  it("sends an empty photoKeys list for a new pit entry", () => {
    const doc = formEntryDocument({
      ...base,
      kind: "pit",
      config: pitConfig,
      values: {},
    });
    expect(doc.photoKeys).toEqual([]);
  });

  it("matches the stored prescout document", () => {
    const doc = formEntryDocument({
      ...base,
      kind: "prescout",
      config: prescoutConfig,
      values: {
        watchedEvent: "2026txhou",
        matchType: "qual",
        matchNumber: 16,
        autoFuelScored: "7",
        climbSeconds: 0,
      },
    });
    const { updatedAtTs, ...rest } = doc;
    expect(rest).toEqual(prescoutFixture);
    expect(updatedAtTs).toEqual(stamp);
    expect("photoKeys" in doc).toBe(false);
  });

  it("caps the author name like the rules do", () => {
    const doc = formEntryDocument({
      ...base,
      kind: "prescout",
      config: prescoutConfig,
      values: {},
      authorDisplayName: "x".repeat(200),
    });
    expect(String(doc.authorDisplayName)).toHaveLength(128);
  });
});

describe("firestore.rules", () => {
  it("lists every key the pit document carries", () => {
    const allowed = ruleKeys("isValidPitScoutEntry");
    const doc = formEntryDocument({
      ...base,
      kind: "pit",
      config: pitConfig,
      values: {},
    });
    expect(allowed.length).toBeGreaterThan(0);
    for (const key of Object.keys(doc)) expect(allowed).toContain(key);
  });

  it("lets a pit entry carry the active event, or none", () => {
    expect(ruleKeys("isValidPitScoutEntry")).toContain("eventKey");
    const rules = readFileSync(
      new URL("../../../firestore.rules", import.meta.url),
      "utf8",
    );
    const body = rules.slice(rules.indexOf("function isValidPitScoutEntry("));
    expect(
      body.slice(0, body.indexOf("function isValidPrescoutEntry")),
    ).toMatch(/data\.eventKey is string\s*&&\s*data\.eventKey\.size\(\) <= 64/);
  });

  it("lists every key the prescout document carries", () => {
    const allowed = ruleKeys("isValidPrescoutEntry");
    const doc = formEntryDocument({
      ...base,
      kind: "prescout",
      config: prescoutConfig,
      values: {},
    });
    expect(allowed.length).toBeGreaterThan(0);
    for (const key of Object.keys(doc)) expect(allowed).toContain(key);
  });
});
