import { describe, expect, it } from "vitest";
import {
  addStroke,
  type Board,
  canMoveSide,
  canRedo,
  canUndo,
  clearAll,
  clearPhase,
  emptyHistory,
  erase,
  maxUndo,
  moveMarker,
  moveTeamSide,
  placeAll,
  placeLabel,
  placeMarker,
  redo,
  setNote,
  undo,
  updateLabel,
} from "./edit";
import { type Marker, newSession, penColor, type Stroke } from "./model";

const start = (): Board => ({
  session: newSession({
    id: "b",
    eventKey: "2027test",
    matchNumber: 1,
    alliance: "Red",
    teamNumbers: [],
    fieldId: "f",
    author: { uid: "u", displayName: "Lead A" },
    nowMs: 1000,
  }),
  history: emptyHistory(),
});

const line = (x: number): Stroke => ({
  phase: "auton",
  legend: false,
  color: penColor,
  points: [
    { x, y: 0.1 },
    { x, y: 0.9 },
  ],
});

const robot = (team: number, x = 0.5): Marker => ({
  phase: "auton",
  position: { x, y: 0.5 },
  team,
  label: null,
  alliance: "Red",
});

describe("strokes", () => {
  it("adds a stroke without changing the board it came from", () => {
    const before = start();
    const after = addStroke(before, "auton", line(0.2), 2000);
    expect(before.session.strokes.auton).toHaveLength(0);
    expect(after.session.strokes.auton).toHaveLength(1);
    expect(after.session.updatedMs).toBe(2000);
  });

  it("never stamps behind the revision it replaces", () => {
    const after = addStroke(start(), "auton", line(0.2), 500);
    expect(after.session.updatedMs).toBe(1000);
  });

  it("keeps each phase apart", () => {
    const b = addStroke(start(), "teleop", line(0.2), 2000);
    expect(b.session.strokes.auton).toHaveLength(0);
    expect(canUndo(b.history, "auton")).toBe(false);
    expect(canUndo(b.history, "teleop")).toBe(true);
  });
});

describe("undo and redo", () => {
  it("steps back and forward", () => {
    let b = addStroke(start(), "auton", line(0.2), 2000);
    b = addStroke(b, "auton", line(0.4), 3000);
    b = undo(b, "auton", 4000);
    expect(b.session.strokes.auton).toHaveLength(1);
    expect(canRedo(b.history, "auton")).toBe(true);
    b = redo(b, "auton", 5000);
    expect(b.session.strokes.auton).toHaveLength(2);
    expect(canRedo(b.history, "auton")).toBe(false);
  });

  it("drops redo when a new edit starts", () => {
    let b = addStroke(start(), "auton", line(0.2), 2000);
    b = undo(b, "auton", 3000);
    b = addStroke(b, "auton", line(0.4), 4000);
    expect(canRedo(b.history, "auton")).toBe(false);
  });

  it("does nothing with nothing to undo", () => {
    const b = start();
    expect(undo(b, "auton", 2000)).toBe(b);
    expect(redo(b, "auton", 2000)).toBe(b);
  });

  it("keeps the newest 50 steps", () => {
    let b = start();
    for (let i = 0; i < maxUndo + 10; i++) {
      b = addStroke(b, "auton", line(i / 100), 2000 + i);
    }
    expect(b.history.undo.auton).toHaveLength(maxUndo);
  });

  it("does not roll back a note typed after a stroke", () => {
    let b = addStroke(start(), "auton", line(0.2), 2000);
    b = setNote(b, "auton", "go left", 3000);
    b = undo(b, "auton", 4000);
    expect(b.session.strokes.auton).toHaveLength(0);
    expect(b.session.notes.auton).toBe("go left");
  });
});

describe("clearPhase", () => {
  it("clears strokes, robots and the note, and undo brings all back", () => {
    let b = addStroke(start(), "auton", line(0.2), 2000);
    b = placeMarker(b, "auton", robot(1111), 3000);
    b = setNote(b, "auton", "go left", 4000);
    b = clearPhase(b, "auton", 5000);
    expect(b.session.strokes.auton).toHaveLength(0);
    expect(b.session.markers.auton).toHaveLength(0);
    expect(b.session.notes.auton).toBe("");
    b = undo(b, "auton", 6000);
    expect(b.session.strokes.auton).toHaveLength(1);
    expect(b.session.markers.auton).toHaveLength(1);
    expect(b.session.notes.auton).toBe("go left");
    b = redo(b, "auton", 7000);
    expect(b.session.notes.auton).toBe("");
  });

  it("leaves the other phases alone", () => {
    let b = addStroke(start(), "teleop", line(0.2), 2000);
    b = clearPhase(b, "auton", 3000);
    expect(b.session.strokes.teleop).toHaveLength(1);
  });
});

describe("clearAll", () => {
  it("clears every phase and undo brings each one back on its own", () => {
    let b = addStroke(start(), "auton", line(0.2), 2000);
    b = placeMarker(b, "auton", robot(1111), 3000);
    b = addStroke(b, "teleop", { ...line(0.4), phase: "teleop" }, 3500);
    b = setNote(b, "endgame", "park", 4000);
    b = clearAll(b, 5000);
    for (const p of ["auton", "teleop", "endgame"] as const) {
      expect(b.session.strokes[p]).toHaveLength(0);
      expect(b.session.markers[p]).toHaveLength(0);
      expect(b.session.notes[p]).toBe("");
    }
    expect(b.session.updatedMs).toBe(5000);
    b = undo(b, "teleop", 6000);
    expect(b.session.strokes.teleop).toHaveLength(1);
    expect(b.session.strokes.auton).toHaveLength(0);
    b = undo(b, "endgame", 7000);
    expect(b.session.notes.endgame).toBe("park");
  });
});

describe("markers", () => {
  it("places a team once per phase", () => {
    let b = placeMarker(start(), "auton", robot(1111), 2000);
    const again = placeMarker(b, "auton", robot(1111, 0.7), 3000);
    expect(again).toBe(b);
    b = placeMarker(b, "teleop", { ...robot(1111), phase: "teleop" }, 3000);
    expect(b.session.markers.teleop).toHaveLength(1);
  });

  it("moves one marker as one undo step", () => {
    let b = placeMarker(start(), "auton", robot(1111), 2000);
    const m = b.session.markers.auton[0] as Marker;
    b = moveMarker(b, "auton", m, { x: 0.9, y: 0.1 }, 3000);
    expect(b.session.markers.auton[0]?.position).toEqual({ x: 0.9, y: 0.1 });
    b = undo(b, "auton", 4000);
    expect(b.session.markers.auton[0]?.position).toEqual({ x: 0.5, y: 0.5 });
  });

  it("ignores a move of a marker that is gone", () => {
    const b = placeMarker(start(), "auton", robot(1111), 2000);
    expect(moveMarker(b, "auton", robot(1111), { x: 0, y: 0 }, 3000)).toBe(b);
  });

  it("places all six at the walls, red left and blue right, top to bottom", () => {
    const robots = [
      ...[1111, 2222, 3333].map((team) => ({ team, side: "red" as const })),
      ...[4444, 5555, 6666].map((team) => ({ team, side: "blue" as const })),
    ];
    const b = placeAll(start(), "teleop", robots, 2000);
    const at = (team: number) =>
      b.session.markers.teleop.find((m) => m.team === team);
    expect(at(1111)?.position).toEqual({ x: 0.125, y: 0.2 });
    expect(at(3333)?.position).toEqual({ x: 0.125, y: 0.8 });
    expect(at(4444)?.position).toEqual({ x: 0.875, y: 0.2 });
    expect(at(6666)?.alliance).toBe("Blue");
    expect(b.session.markers.teleop.every((m) => m.phase === "teleop")).toBe(
      true,
    );
  });
});

describe("erase", () => {
  const board = () => {
    let b = addStroke(start(), "auton", line(0.2), 2000);
    b = addStroke(b, "auton", line(0.4), 3000);
    return placeMarker(b, "auton", robot(1111), 4000);
  };

  it("removes the one hit item", () => {
    const b = board();
    const target = b.session.strokes.auton[0] as Stroke;
    const after = erase(
      b,
      "auton",
      { kind: "stroke", item: target },
      true,
      5000,
    );
    expect(after.session.strokes.auton).toHaveLength(1);
    expect(after.session.markers.auton).toHaveLength(1);
  });

  it("shares one undo step across a drag", () => {
    const b = board();
    const [first, second] = b.session.strokes.auton as [Stroke, Stroke];
    const marker = b.session.markers.auton[0] as Marker;
    let after = erase(b, "auton", { kind: "stroke", item: first }, true, 5000);
    after = erase(
      after,
      "auton",
      { kind: "stroke", item: second },
      false,
      5001,
    );
    after = erase(
      after,
      "auton",
      { kind: "marker", item: marker },
      false,
      5002,
    );
    expect(after.session.strokes.auton).toHaveLength(0);
    expect(after.session.markers.auton).toHaveLength(0);
    after = undo(after, "auton", 6000);
    expect(after.session.strokes.auton).toHaveLength(2);
    expect(after.session.markers.auton).toHaveLength(1);
  });

  it("ignores an item that is already gone", () => {
    const b = board();
    const target = b.session.strokes.auton[0] as Stroke;
    const once = erase(
      b,
      "auton",
      { kind: "stroke", item: target },
      true,
      5000,
    );
    expect(
      erase(once, "auton", { kind: "stroke", item: target }, false, 5001),
    ).toBe(once);
  });
});

describe("labels", () => {
  it("places, edits, moves, erases and undoes per phase", () => {
    const label = { x: 0.2, y: 0.3, text: "Defend" };
    let b = placeLabel(start(), "teleop", label, 2000);
    expect(b.session.labels.auton).toEqual([]);
    const edited = { ...label, text: "Block" };
    b = updateLabel(b, "teleop", label, edited, 2001);
    const moved = { ...edited, x: 0.8 };
    b = updateLabel(b, "teleop", edited, moved, 2002);
    b = erase(b, "teleop", { kind: "label", item: moved }, true, 2003);
    expect(b.session.labels.teleop).toEqual([]);
    b = undo(b, "teleop", 2004);
    expect(b.session.labels.teleop).toEqual([moved]);
    b = undo(b, "teleop", 2005);
    expect(b.session.labels.teleop).toEqual([edited]);
    b = undo(b, "teleop", 2006);
    expect(b.session.labels.teleop).toEqual([label]);
    b = undo(b, "teleop", 2007);
    expect(b.session.labels.teleop).toEqual([]);
  });
});

describe("moving a team to the other side", () => {
  const practice = (teams: number[], opponents: number[]): Board => {
    const b = start();
    return {
      ...b,
      session: { ...b.session, teamNumbers: teams, opponentTeams: opponents },
    };
  };

  it("moves a team of ours to the opponents, sorted, and stamps it", () => {
    const b = practice([1111, 2222, 4444], [4444]);
    const next = moveTeamSide(b, 2222, 5000);
    expect(next.session.opponentTeams).toEqual([2222, 4444]);
    expect(next.session.updatedMs).toBe(5000);
    expect(b.session.opponentTeams).toEqual([4444]);
  });

  it("moves an opponent back to our side", () => {
    const next = moveTeamSide(practice([1111, 4444], [4444]), 4444, 5000);
    expect(next.session.opponentTeams).toEqual([]);
  });

  it("never stamps behind the stored revision", () => {
    const b = practice([1111, 4444], []);
    expect(moveTeamSide(b, 1111, 10).session.updatedMs).toBe(1000);
  });

  it("moves the team's markers to the new side and keeps undo", () => {
    const b = practice([1111, 4444], [4444]);
    const placed = placeMarker(
      b,
      "auton",
      {
        phase: "auton",
        position: { x: 0.3, y: 0.3 },
        team: 1111,
        label: null,
        alliance: "Red",
      },
      2000,
    );
    const next = moveTeamSide(placed, 1111, 3000);
    const [moved] = next.session.markers.auton;
    expect(moved?.alliance).toBe(
      placed.session.alliance === "Blue" ? "Red" : "Blue",
    );
    expect(moved?.position).toEqual({ x: 0.3, y: 0.3 });
    expect(next.session.strokes).toBe(placed.session.strokes);
    expect(next.history).toBe(placed.history);
    const back = moveTeamSide(next, 1111, 4000);
    expect(back.session.markers.auton[0]?.alliance).toBe(
      placed.session.markers.auton[0]?.alliance,
    );
  });

  it("refuses a team that is not on the board", () => {
    const b = practice([1111], []);
    expect(canMoveSide(b.session, 9999)).toBe(false);
    expect(moveTeamSide(b, 9999, 5000)).toBe(b);
  });

  it("holds each side to six teams", () => {
    const full = practice([1, 2, 3, 4, 5, 6, 7, 8], [4, 5, 6, 7, 8]);
    expect(canMoveSide(full.session, 1)).toBe(true);
    const six = moveTeamSide(full, 1, 5000);
    expect(six.session.opponentTeams).toHaveLength(6);
    expect(canMoveSide(six.session, 2)).toBe(false);
    expect(moveTeamSide(six, 2, 6000)).toBe(six);
    expect(canMoveSide(six.session, 1)).toBe(true);
  });

  it("refuses to fill our side past six", () => {
    const five = practice([1, 2, 3, 4, 5, 6], [6]);
    expect(canMoveSide(five.session, 6)).toBe(true);
    const six = practice([1, 2, 3, 4, 5, 6, 7], [7]);
    expect(canMoveSide(six.session, 7)).toBe(false);
  });
});
