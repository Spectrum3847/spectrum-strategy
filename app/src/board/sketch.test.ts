import { describe, expect, it } from "vitest";
import { penColor, type Stroke } from "./model";
import {
  emptySketch,
  eraseAt,
  isFull,
  maxStrokes,
  sketchFromJson,
  sketchIsEmpty,
  sketchLabel,
  sketchToJson,
  strokesFromList,
  strokesToJson,
} from "./sketch";

const line = (y: number): Stroke => ({
  phase: "auton",
  legend: false,
  color: penColor,
  points: [
    { x: 0.1, y },
    { x: 0.9, y },
  ],
});

describe("sketch json", () => {
  it("writes only the phases that have lines", () => {
    const sketch = { ...emptySketch(), teleop: [line(0.5)] };
    expect(sketchToJson(sketch)).toEqual({
      teleop: [
        {
          phase: "auton",
          colorValue: penColor,
          points: [
            { x: 0.1, y: 0.5 },
            { x: 0.9, y: 0.5 },
          ],
        },
      ],
    });
  });

  it("is null when nothing is drawn", () => {
    expect(sketchToJson(emptySketch())).toBeNull();
    expect(sketchIsEmpty(emptySketch())).toBe(true);
  });

  it("reads stored sketches and skips what it cannot", () => {
    const sketch = sketchFromJson({
      auton: [
        {
          phase: "auton",
          colorValue: 4282384480,
          points: [{ x: 0.2, y: 0.3 }, { x: "bad" }, { x: 0.4, y: 0.5 }],
        },
        "junk",
      ],
      mars: [line(0.1)],
    });
    expect(sketch.auton).toHaveLength(1);
    expect(sketch.auton[0]?.points).toHaveLength(2);
    expect(sketch.auton[0]?.color).toBe(4282384480);
    expect(sketch.teleop).toEqual([]);
  });

  it("survives a round trip", () => {
    const sketch = { ...emptySketch(), endgame: [line(0.2), line(0.8)] };
    expect(sketchFromJson(sketchToJson(sketch))).toEqual(sketch);
  });

  it("reads a T-REx list and ignores a non-list", () => {
    const strokes = [line(0.4)];
    expect(strokesFromList(strokesToJson(strokes))).toEqual(strokes);
    expect(strokesFromList("x")).toEqual([]);
    expect(strokesFromList(undefined)).toEqual([]);
  });
});

describe("erasing", () => {
  const size = { w: 1000, h: 500 };
  it("removes the line under the pointer and only that one", () => {
    const strokes = [line(0.2), line(0.8)];
    const next = eraseAt(strokes, 500, 100, size);
    expect(next).toEqual([strokes[1]]);
  });

  it("returns the same list when nothing is near", () => {
    const strokes = [line(0.2)];
    expect(eraseAt(strokes, 500, 400, size)).toBe(strokes);
  });
});

describe("limits", () => {
  it("is full at the stroke cap", () => {
    const sketch = {
      ...emptySketch(),
      auton: Array.from({ length: maxStrokes }, () => line(0.5)),
    };
    expect(isFull(sketch, "auton")).toBe(true);
    expect(isFull(emptySketch(), "auton")).toBe(false);
  });
});

describe("sketchLabel", () => {
  it("names the surface, phase and state", () => {
    expect(sketchLabel("Scouting drawing", "auton", 0, false)).toBe(
      "Scouting drawing, Auto phase, empty",
    );
    expect(sketchLabel("Trait drawing", null, 2, true)).toBe(
      "Trait drawing, 2 drawings, read only",
    );
  });
});
