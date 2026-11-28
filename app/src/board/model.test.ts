import { readFileSync } from "node:fs";
import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import {
  boardSides,
  newest,
  newSession,
  parseSession,
  penColor,
  sessionDoc,
  sessionJson,
} from "./model";

const latest = "2026-rebuilt";
const stamp = Date.UTC(2027, 2, 5, 18, 4, 5, 123);
const lead = { uid: "uid-1", displayName: "Lead A" };

const fixture = {
  id: "board-1",
  eventKey: "2027test",
  eventName: "",
  matchNumber: 3,
  alliance: "Red",
  teamNumbers: [1111, 2222, 3333, 4444, 5555, 6666],
  selectedPhase: "teleop",
  selectedTool: "draw",
  selectedFieldId: "2026-rebuilt",
  selectedRobotTeam: null,
  updatedAt: "2027-03-05T18:04:05.123Z",
  authorUid: "uid-1",
  authorDisplayName: "Lead A",
  strokesByPhase: {
    auton: [
      {
        phase: "auton",
        colorValue: 4282122336,
        points: [
          { x: 0.1, y: 0.2 },
          { x: 0.3, y: 0.4 },
        ],
      },
    ],
    teleop: [
      {
        phase: "teleop",
        isLegend: true,
        colorValue: 4282122336,
        points: [{ x: 0.5, y: 0.5 }],
      },
    ],
    endgame: [],
  },
  markersByPhase: {
    auton: [
      {
        phase: "auton",
        position: { x: 0.125, y: 0.2 },
        teamNumber: 1111,
        label: null,
        alliance: "Red",
      },
    ],
    teleop: [],
    endgame: [],
  },
  labelsByPhase: {
    auton: [{ x: 0.3, y: 0.4, text: "Defend" }],
    teleop: [],
    endgame: [],
  },
  notesByPhase: { auton: "", teleop: "push left", endgame: "" },
};

const withStamp = { ...fixture, updatedAtTs: Timestamp.fromMillis(stamp) };

function ruleKeys(fn: string): string[] {
  const rules = readFileSync(
    new URL("../../../firestore.rules", import.meta.url),
    "utf8",
  );
  const body = rules.slice(rules.indexOf(`function ${fn}(`));
  const list = /hasOnly\(\[([^\]]*)\]\)/.exec(body)?.[1] ?? "";
  return [...list.matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");
}

describe("sessionDoc", () => {
  it("round-trips the board document including labels", () => {
    const session = parseSession("board-1", withStamp, latest);
    expect(sessionDoc(session, lead)).toEqual(withStamp);
  });

  it("reads a stored board, stamp from updatedAtTs", () => {
    const session = parseSession("x", withStamp, latest);
    expect(session.updatedMs).toBe(stamp);
    expect(session.strokes.auton[0]?.points).toHaveLength(2);
    expect(session.strokes.teleop[0]?.legend).toBe(true);
    expect(session.markers.auton[0]).toMatchObject({
      team: 1111,
      label: null,
      alliance: "Red",
    });
    expect(session.labels.auton[0]?.text).toBe("Defend");
    expect(
      parseSession("x", { ...fixture, labelsByPhase: undefined }, latest).labels
        .auton,
    ).toEqual([]);
    expect(session.notes.teleop).toBe("push left");
  });

  it("reads the text stamp when there is no server stamp", () => {
    expect(parseSession("x", fixture, latest).updatedMs).toBe(stamp);
  });

  it("leaves eventKey out when blank and keeps blank names a string", () => {
    const session = parseSession(
      "board-1",
      { ...fixture, eventKey: "" },
      latest,
    );
    const doc = sessionDoc(session, lead);
    expect("eventKey" in doc).toBe(false);
    expect(doc.eventName).toBe("");
  });

  it("keeps the first author and fills a blank one", () => {
    const other = { uid: "uid-2", displayName: "Lead B" };
    const kept = parseSession("board-1", withStamp, latest);
    expect(sessionDoc(kept, other)).toMatchObject({
      authorUid: "uid-1",
      authorDisplayName: "Lead A",
    });
    const blank = parseSession(
      "board-1",
      { ...fixture, authorUid: "", authorDisplayName: "" },
      latest,
    );
    expect(sessionDoc(blank, other)).toMatchObject({
      authorUid: "uid-2",
      authorDisplayName: "Lead B",
    });
  });

  it("never writes a missing author name, which the rules need", () => {
    const blank = parseSession(
      "board-1",
      { ...fixture, authorUid: "" },
      latest,
    );
    const doc = sessionDoc(
      { ...blank, authorDisplayName: "" },
      { uid: "uid-2", displayName: "" },
    );
    expect(doc.authorDisplayName).toBe("");
  });

  it("round-trips through the local copy", () => {
    const session = parseSession("board-1", withStamp, latest);
    expect(parseSession("board-1", sessionJson(session), latest)).toEqual(
      session,
    );
  });

  it("starts a new board with every phase present and the one pen color", () => {
    const fresh = newSession({
      id: "n",
      eventKey: "2027test",
      matchNumber: 7,
      alliance: "Blue",
      teamNumbers: [3, 1, 2, 1],
      fieldId: latest,
      author: lead,
      nowMs: stamp,
    });
    expect(fresh.teamNumbers).toEqual([1, 2, 3]);
    const doc = sessionDoc(fresh, lead);
    expect(Object.keys(doc.strokesByPhase as object)).toEqual([
      "auton",
      "teleop",
      "endgame",
    ]);
    expect(penColor).toBe(4282122336);
  });
});

describe("opponentTeams", () => {
  const withSides = (opponentTeams: unknown) =>
    parseSession(
      "board-1",
      {
        ...fixture,
        alliance: "Blue",
        teamNumbers: [1, 2, 3, 4],
        opponentTeams,
      },
      latest,
    );

  it("is empty for a document from before the field", () => {
    const session = parseSession("board-1", fixture, latest);
    expect(session.opponentTeams).toEqual([]);
    expect("opponentTeams" in sessionJson(session)).toBe(false);
  });

  it("keeps ints that are in teamNumbers, once each, and drops the rest", () => {
    expect(withSides([4, "x", 9, 3, 4, null]).opponentTeams).toEqual([3, 4]);
    expect(withSides("nope").opponentTeams).toEqual([]);
  });

  it("is written when set and survives the local copy", () => {
    const session = withSides([3, 4]);
    expect(sessionJson(session).opponentTeams).toEqual([3, 4]);
    expect(sessionDoc(session, lead).opponentTeams).toEqual([3, 4]);
    expect(parseSession("board-1", sessionJson(session), latest)).toEqual(
      session,
    );
  });

  it("is set by newSession only for teams on the board", () => {
    const fresh = newSession({
      id: "n",
      eventKey: "2027test",
      matchNumber: 7,
      alliance: "Red",
      teamNumbers: [1, 2, 3],
      opponentTeams: [3, 9, 3],
      fieldId: latest,
      author: lead,
      nowMs: stamp,
    });
    expect(fresh.opponentTeams).toEqual([3]);
  });
});

describe("boardSides", () => {
  it("puts opponents on the side we are not", () => {
    expect(boardSides(withSidesFor("Red"))).toEqual({
      red: [1, 2],
      blue: [3, 4],
    });
    expect(boardSides(withSidesFor("Blue"))).toEqual({
      red: [3, 4],
      blue: [1, 2],
    });
  });

  it("keeps every team on our side when there are no opponents", () => {
    const session = parseSession("board-1", fixture, latest);
    expect(boardSides(session)).toEqual({
      red: [1111, 2222, 3333, 4444, 5555, 6666],
      blue: [],
    });
    expect(boardSides({ ...session, alliance: "Blue" })).toEqual({
      red: [],
      blue: [1111, 2222, 3333, 4444, 5555, 6666],
    });
  });
});

function withSidesFor(alliance: string) {
  return parseSession(
    "board-1",
    { ...fixture, alliance, teamNumbers: [1, 2, 3, 4], opponentTeams: [3, 4] },
    latest,
  );
}

describe("parseSession", () => {
  it("skips a bad point, a marker with no position and an unknown phase key", () => {
    const session = parseSession(
      "fallback",
      {
        id: " ",
        strokesByPhase: {
          auton: [
            { points: [{ x: 1, y: 2 }, { x: "no" }, null, { x: 3, y: 4 }] },
            "junk",
          ],
          sideways: [{ points: [] }],
        },
        markersByPhase: {
          auton: [
            { position: { x: 0.5 } },
            { position: { x: 0.5, y: 0.5 }, teamNumber: "1111" },
          ],
        },
        selectedPhase: "later",
        matchNumber: "x",
        selectedFieldId: " ",
      },
      latest,
    );
    expect(session.id).toBe("fallback");
    expect(session.strokes.auton).toHaveLength(1);
    expect(session.strokes.auton[0]?.points).toHaveLength(2);
    expect(session.markers.auton).toHaveLength(1);
    expect(session.markers.auton[0]?.team).toBeNull();
    expect(session.selectedPhase).toBe("auton");
    expect(session.matchNumber).toBe(1);
    expect(session.selectedFieldId).toBe(latest);
  });
});

describe("newest", () => {
  it("picks the board with the latest stamp", () => {
    const a = parseSession("a", { ...withStamp, id: "a" }, latest);
    const b = { ...a, id: "b", updatedMs: a.updatedMs + 5 };
    expect(newest([a, b])?.id).toBe("b");
    expect(newest([])).toBeNull();
  });
});

describe("firestore.rules", () => {
  it("lists every key the board document carries", () => {
    const allowed = ruleKeys("isValidStrategyBoard");
    expect(allowed.length).toBeGreaterThan(0);
    for (const key of Object.keys(
      sessionDoc(parseSession("b", fixture, latest), lead),
    )) {
      expect(allowed).toContain(key);
    }
  });

  it("is given every key the rules need", () => {
    const doc = sessionDoc(parseSession("b", fixture, latest), lead);
    for (const key of [
      "id",
      "matchNumber",
      "alliance",
      "selectedFieldId",
      "authorUid",
      "authorDisplayName",
      "updatedAt",
      "updatedAtTs",
      "teamNumbers",
      "strokesByPhase",
      "markersByPhase",
      "notesByPhase",
      "eventName",
      "selectedPhase",
      "selectedTool",
    ]) {
      expect(doc).toHaveProperty(key);
    }
  });

  it("gives the text stamp the length and range the rules check", () => {
    const text = String(
      sessionDoc(parseSession("b", fixture, latest), lead).updatedAt,
    );
    expect(text.length).toBeGreaterThanOrEqual(20);
    expect(text >= "2020" && text < "2100").toBe(true);
  });
});
