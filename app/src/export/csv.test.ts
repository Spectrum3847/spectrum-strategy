import { describe, expect, it } from "vitest";
import { parseConfig } from "../scout/config";
import {
  buildScoutCsv,
  csvCell,
  type ExportEntry,
  exportFileName,
  scoutAliases,
  stationOfEntry,
} from "./csv";

const config = parseConfig({
  title: "T",
  revision: 1,
  sections: [
    {
      name: "Pre",
      fields: [
        { code: "scouter", title: "Scouter Name", type: "text" },
        { code: "matchNumber", title: "Match", type: "TBA-match-number" },
        {
          code: "robot",
          title: "Driver Station",
          type: "select",
          choices: { R2: "Red 2", B1: "Blue 1", B2: "Blue 2" },
        },
        {
          code: "starting",
          title: "Start",
          type: "select",
          choices: { "0": "No Show", "1": "Left" },
        },
      ],
    },
    {
      name: "Auto",
      fields: [
        { code: "fuel", title: "Fuel Scored", type: "counter" },
        { code: "acc", title: "Accuracy", type: "range", max: 100 },
        { code: "defense", title: "Defense", type: "boolean" },
        {
          code: "traits",
          title: "Traits",
          type: "checkbox-select",
          choices: { a: "A", b: "B" },
        },
      ],
    },
    {
      name: "End",
      fields: [
        {
          code: "climb",
          title: "Climb",
          type: "select",
          choices: { "1": "None", "2": "L1" },
        },
        { code: "comments", title: "Comments", type: "text" },
        { code: "email", title: "Email", type: "text" },
        { code: "notes", title: "Notes", type: "long-text" },
      ],
    },
  ],
});

const entries: ExportEntry[] = [
  {
    tbaMatchKey: "2027test_qm2",
    teamNumber: 2222,
    scoutName: "Sam Scout",
    createdAt: "2027-03-05T18:04:05.123Z",
    updatedAt: "2027-03-05T18:10:00.000Z",
    fieldValues: {
      scouter: "Sam Scout",
      robot: "R2",
      starting: "1",
      fuel: 7,
      acc: 80,
      defense: true,
      traits: "a,b",
      climb: "2",
      comments: 'Fast, "clean" climb',
      email: "sam@example.com",
    },
  },
  {
    tbaMatchKey: "2027test_qm1",
    teamNumber: 3333,
    scoutName: "sam scout ",
    updatedAt: "2027-03-05T17:05:00.000Z",
    fieldValues: {
      robot: "B2",
      starting: "0",
      fuel: 4,
      defense: false,
      climb: "1",
      comments: "",
    },
  },
  {
    tbaMatchKey: "2027test_qm1",
    teamNumber: 1111,
    scoutName: "Pat Scout",
    updatedAt: "2027-03-05T17:00:00.000Z",
    fieldValues: {
      robot: "B1",
      starting: "0",
      fuel: 0,
      defense: false,
      climb: "1",
      comments: "=SUM(1)",
      notes: "Line one\nline two",
    },
  },
];

const hidden = [
  "Event,Match,Team,Station,Created (UTC),Updated (UTC),Driver Station,Start,Fuel Scored,Defense,Climb,Scout",
  "2027test,2027test_qm1,1111,B1,,2027-03-05T17:00:00.000Z,Blue 1,No Show,0,false,None,Scout 1",
  "2027test,2027test_qm1,3333,B2,,2027-03-05T17:05:00.000Z,Blue 2,,4,false,None,Scout 2",
  "2027test,2027test_qm2,2222,R2,2027-03-05T18:04:05.123Z,2027-03-05T18:10:00.000Z,Red 2,Left,7,true,L1,Scout 2",
].join("\r\n");

describe("buildScoutCsv", () => {
  it("matches the expected columns with names hidden and no comments", () => {
    expect(
      buildScoutCsv(config, entries, "2027test", {
        hideNames: true,
        includeComments: false,
      }),
    ).toBe(hidden);
  });

  it("shows trimmed names when names are not hidden", () => {
    const csv = buildScoutCsv(config, entries, "2027test", {
      hideNames: false,
      includeComments: false,
    });
    const rows = csv.split("\r\n");
    expect(rows.map((r) => r.split(",").at(-1))).toEqual([
      "Scout",
      "Pat Scout",
      "sam scout",
      "Sam Scout",
    ]);
  });

  it("adds comment columns, escaped, but never name or email fields", () => {
    const csv = buildScoutCsv(config, entries, "2027test", {
      hideNames: true,
      includeComments: true,
    });
    const rows = csv.split("\r\n");
    expect(rows[0]).toBe(`${hidden.split("\r\n")[0]},Comments,Notes`);
    expect(rows[1]).toBe(
      `${hidden.split("\r\n")[1]},'=SUM(1),"Line one\nline two"`,
    );
    expect(rows[2]).toBe(`${hidden.split("\r\n")[2]},,`);
    expect(rows[3]).toBe(`${hidden.split("\r\n")[3]},"Fast, ""clean"" climb",`);
    expect(csv).not.toContain("sam@example.com");
  });

  it("gives the same scout the same number whatever the input order", () => {
    const options = { hideNames: true, includeComments: false };
    const forward = buildScoutCsv(config, entries, "2027test", options);
    const reversed = buildScoutCsv(
      config,
      [...entries].reverse(),
      "2027test",
      options,
    );
    expect(reversed).toBe(forward);
  });

  it("is only the header for no entries", () => {
    expect(
      buildScoutCsv(config, [], "2027test", {
        hideNames: true,
        includeComments: false,
      }),
    ).toBe(hidden.split("\r\n")[0]);
  });

  it("puts finals after qualifications", () => {
    const rows = buildScoutCsv(
      config,
      ["2027test_f1m1", "2027test_qm9", "2027test_sf2m1"].map((key) => ({
        ...(entries[0] as ExportEntry),
        tbaMatchKey: key,
      })),
      "2027test",
      { hideNames: true, includeComments: false },
    ).split("\r\n");
    expect(rows.slice(1).map((r) => r.split(",")[1])).toEqual([
      "2027test_qm9",
      "2027test_sf2m1",
      "2027test_f1m1",
    ]);
  });
});

describe("csvCell", () => {
  it("quotes a cell with a comma, quote or line break", () => {
    expect(csvCell("a,b")).toBe('"a,b"');
    expect(csvCell('say "hi"')).toBe('"say ""hi"""');
    expect(csvCell("a\r\nb")).toBe('"a\r\nb"');
    expect(csvCell("plain")).toBe("plain");
  });

  it("prefixes a quote on a formula start, except a plain number", () => {
    expect(csvCell("=1+1")).toBe("'=1+1");
    expect(csvCell("+cmd")).toBe("'+cmd");
    expect(csvCell("-x")).toBe("'-x");
    expect(csvCell("@a")).toBe("'@a");
    expect(csvCell("-5")).toBe("-5");
    expect(csvCell("-5.5")).toBe("-5.5");
    expect(csvCell("+3")).toBe("+3");
  });
});

describe("stationOfEntry", () => {
  it("reads a select value or a team-and-robot map, normalized", () => {
    expect(stationOfEntry({ a: "Red 2" })).toBe("R2");
    expect(stationOfEntry({ a: { teamNumber: 1, robotPosition: "b3" } })).toBe(
      "B3",
    );
    expect(stationOfEntry({ a: "hello" })).toBe("");
  });

  it("reads two stations that disagree as none", () => {
    expect(stationOfEntry({ a: "R1", b: "B1" })).toBe("");
    expect(stationOfEntry({ a: "R1", b: "Red 1" })).toBe("R1");
  });
});

describe("scoutAliases", () => {
  it("numbers names by first appearance and ignores case", () => {
    const alias = scoutAliases();
    expect(alias("Ana")).toBe("Scout 1");
    expect(alias("Ben")).toBe("Scout 2");
    expect(alias(" ana ")).toBe("Scout 1");
    expect(alias("")).toBe("");
  });
});

describe("exportFileName", () => {
  it("names the file after the event", () => {
    expect(exportFileName("2027Test")).toBe("2027test-scout-entries.csv");
    expect(exportFileName("")).toBe("scout-entries.csv");
  });
});
