import { describe, expect, it } from "vitest";
import pitBundled from "../../../assets/pit_scout_config_default.json";
import prescoutBundled from "../../../assets/prescout_config_default.json";
import type { FormEntry, TrexReport } from "../data/parse";
import { parseConfig } from "../scout/config";
import { allNotes, type TeamComment } from "./format";

const pitConfig = parseConfig(pitBundled);
const prescoutConfig = parseConfig(prescoutBundled);

const record = (
  id: string,
  updatedAt: string,
  fieldValues: Record<string, unknown>,
): FormEntry => ({
  id,
  teamNumber: 1111,
  eventKey: "2027test",
  fieldValues,
  authorUid: "u1",
  scoutName: "Scout A",
  updatedAt,
});

const scout: TeamComment = {
  id: "e1:comments",
  source: "Scout",
  text: "Lost drive power",
  fieldTitle: "Comments",
  scoutName: "Scout B",
  updatedAt: "2027-03-01T12:00:00.000Z",
  matchKey: "2027test_qm1",
};

const trex: TrexReport = {
  id: "t1",
  trait: "defense",
  teamNumber: 1111,
  matchNumber: 5,
  eventName: "",
  eventKey: "2027test",
  report: " Pins for too long ",
  rating: 2,
  scoutName: "Scout C",
  updatedAt: "2027-03-01T11:00:00.000Z",
};

describe("allNotes", () => {
  it("collects every source, newest first", () => {
    const notes = allNotes({
      scout: [scout],
      pit: {
        config: pitConfig,
        entries: [
          record("p", "2027-03-01T09:00:00.000Z", {
            comments: "Bumper is loose",
            autoDescription: "Two piece left",
            swerveModuleType: "MK4i",
          }),
        ],
      },
      prescout: {
        config: prescoutConfig,
        entries: [
          record("q", "2027-02-01T09:00:00.000Z", {
            comments: "Fast cycles",
            videoUrl: "https://example.com/v",
          }),
        ],
      },
      trex: [trex, { ...trex, id: "t2", report: "  " }],
      note: {
        id: "2027test_1111",
        eventKey: "2027test",
        teamNumber: 1111,
        text: "Ally with a defender",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        updatedMs: Date.parse("2027-03-01T10:00:00Z"),
      },
    });
    expect(notes.map((n) => [n.source, n.text])).toEqual([
      ["Scout", "Lost drive power"],
      ["T-REx", "Pins for too long"],
      ["Team note", "Ally with a defender"],
      ["Pit", "Two piece left"],
      ["Pit", "Bumper is loose"],
      ["Prescout", "Fast cycles"],
    ]);
    expect(notes[1]?.fieldTitle).toMatch(/rated 2 of 5, match 5$/);
  });

  it("leaves out a blank team note", () => {
    const notes = allNotes({
      scout: [],
      pit: { config: pitConfig, entries: [] },
      prescout: { config: prescoutConfig, entries: [] },
      trex: [],
      note: {
        id: "2027test_1111",
        eventKey: "2027test",
        teamNumber: 1111,
        text: "  ",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        updatedMs: 1,
      },
    });
    expect(notes).toEqual([]);
  });
});
