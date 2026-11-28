import { describe, expect, it } from "vitest";
import {
  argbToHsl,
  clampView,
  directionColor,
  distanceToSegment,
  fieldSize,
  findHit,
  homeView,
  maxScale,
  nextPoint,
  panView,
  pinchView,
  type Stage,
  strokeParts,
  zoomAt,
} from "./geometry";
import { type Marker, penColor, type Stroke } from "./model";

const size = { w: 1000, h: 500 };

describe("directionColor", () => {
  it("starts at the base purple and gets lighter along the line", () => {
    const base = argbToHsl(penColor);
    expect(base.l).toBeCloseTo(0.188, 2);
    const lightness = (t: number) =>
      Number(/(\d+\.\d)%\)$/.exec(directionColor(penColor, t))?.[1]);
    expect(lightness(0)).toBeCloseTo(18.8, 0);
    expect(lightness(1)).toBeCloseTo(60.8, 0);
    expect(lightness(0.5)).toBeGreaterThan(lightness(0));
  });

  it("stops short of white", () => {
    const light = argbToHsl(0xffd0c0ff);
    expect(light.l).toBeGreaterThan(0.78);
    expect(directionColor(0xffd0c0ff, 1)).toContain("78.0%");
  });
});

describe("strokeParts", () => {
  const straight = (n: number) =>
    Array.from({ length: n }, (_, i) => ({ x: (i / (n - 1)) * 0.3, y: 0.5 }));

  it("draws nothing for a stroke with no length", () => {
    expect(strokeParts([{ x: 0.5, y: 0.5 }], penColor, size).bands).toEqual([]);
    expect(
      strokeParts(
        [
          { x: 0.5, y: 0.5 },
          { x: 0.5, y: 0.5 },
        ],
        penColor,
        size,
      ).arrows,
    ).toEqual([]);
  });

  it("covers the whole line in at most 16 joined bands", () => {
    const { bands } = strokeParts(straight(200), penColor, size);
    expect(bands.length).toBeGreaterThan(1);
    expect(bands.length).toBeLessThanOrEqual(16);
    const ends = bands.map((b) => b.points.split(" "));
    for (let i = 1; i < ends.length; i++) {
      expect(ends[i]?.[0]).toBe(ends[i - 1]?.at(-1));
    }
    expect(ends[0]?.[0]).toBe("0.0,250.0");
    expect(ends.at(-1)?.at(-1)).toBe("300.0,250.0");
    expect(new Set(bands.map((b) => b.color)).size).toBe(bands.length);
  });

  it("puts an arrow every 56px along 300px, none near the end", () => {
    const { arrows } = strokeParts(straight(31), penColor, size);
    expect(arrows).toHaveLength(4);
  });

  it("points each arrow the way the line travels", () => {
    const { arrows } = strokeParts(straight(31), penColor, size);
    const d = arrows[0]?.d ?? "";
    const [first, apex, last] = d.match(/-?\d+\.\d,-?\d+\.\d/g) ?? [];
    const x = (p?: string) => Number(p?.split(",")[0]);
    expect(x(first)).toBeLessThan(x(apex));
    expect(x(last)).toBeLessThan(x(apex));
  });
});

describe("findHit", () => {
  const stroke: Stroke = {
    phase: "auton",
    legend: false,
    color: penColor,
    points: [
      { x: 0.1, y: 0.5 },
      { x: 0.9, y: 0.5 },
    ],
  };
  const marker: Marker = {
    phase: "auton",
    position: { x: 0.5, y: 0.5 },
    team: 1111,
    label: null,
    alliance: "Red",
  };

  it("finds a marker before the line under it", () => {
    const hit = findHit([stroke], [marker], 500, 250, size, false, 1);
    expect(hit?.kind).toBe("marker");
  });

  it("finds a line within 16 screen pixels", () => {
    expect(findHit([stroke], [], 300, 264, size, false, 1)?.kind).toBe(
      "stroke",
    );
    expect(findHit([stroke], [], 300, 270, size, false, 1)).toBeNull();
  });

  it("tightens the reach as the view zooms in", () => {
    expect(findHit([stroke], [], 300, 264, size, false, 4)).toBeNull();
    expect(findHit([stroke], [], 300, 253, size, false, 4)?.kind).toBe(
      "stroke",
    );
  });

  it("keeps the legend and the field apart", () => {
    const writing = { ...stroke, legend: true };
    expect(findHit([writing], [], 300, 250, size, false, 1)).toBeNull();
    expect(findHit([stroke], [], 300, 250, size, true, 1)).toBeNull();
    expect(findHit([writing], [], 300, 250, size, true, 1)?.kind).toBe(
      "stroke",
    );
  });

  it("measures to the segment, not the line through it", () => {
    expect(distanceToSegment(0, 0, 10, 0, 20, 0)).toBe(10);
    expect(distanceToSegment(5, 3, 0, 0, 10, 0)).toBe(3);
  });
});

describe("nextPoint", () => {
  it("rounds to four places", () => {
    expect(nextPoint(undefined, { x: 0.123456, y: 0.987654 }, size, 1)).toEqual(
      {
        x: 0.1235,
        y: 0.9877,
      },
    );
  });

  it("drops a sample under 1.5 screen pixels from the last", () => {
    const last = { x: 0.5, y: 0.5 };
    expect(nextPoint(last, { x: 0.5008, y: 0.5 }, size, 1)).toBeNull();
    expect(nextPoint(last, { x: 0.502, y: 0.5 }, size, 1)).not.toBeNull();
    expect(nextPoint(last, { x: 0.5008, y: 0.5 }, size, 4)).not.toBeNull();
  });
});

describe("view", () => {
  const stage: Stage = { sw: 800, sh: 400, fw: 800, fh: 400 };

  it("keeps the field covering the stage", () => {
    const v = clampView({ s: 2, tx: 100, ty: 100 }, stage);
    expect(v).toEqual({ s: 2, tx: 0, ty: 0 });
    expect(clampView({ s: 2, tx: -5000, ty: -5000 }, stage)).toEqual({
      s: 2,
      tx: -800,
      ty: -400,
    });
  });

  it("limits the zoom", () => {
    expect(clampView({ s: 99, tx: 0, ty: 0 }, stage).s).toBe(maxScale);
    expect(clampView({ s: 0.2, tx: 0, ty: 0 }, stage).s).toBe(1);
  });

  it("centres a field smaller than the stage", () => {
    const tall: Stage = { sw: 800, sh: 600, fw: 800, fh: 400 };
    expect(clampView(homeView, tall)).toEqual({ s: 1, tx: 0, ty: 0 });
    const narrow: Stage = { sw: 1000, sh: 400, fw: 800, fh: 400 };
    const v = clampView({ s: 1, tx: 50, ty: 0 }, narrow);
    expect(v.tx).toBe(0);
  });

  it("zooms about a point and keeps it under the finger", () => {
    const v = zoomAt(homeView, stage, 600, 100, 2);
    expect(v.s).toBe(2);
    expect((600 - v.tx) / v.s).toBeCloseTo(600, 5);
    expect((100 - v.ty) / v.s).toBeCloseTo(100, 5);
  });

  it("follows a pinch", () => {
    const from = { x: 400, y: 200, d: 100 };
    const to = { x: 400, y: 200, d: 200 };
    const v = pinchView(homeView, stage, from, to);
    expect(v.s).toBe(2);
    expect(v.tx).toBe(-400);
    const moved = pinchView(homeView, stage, from, { x: 300, y: 200, d: 200 });
    expect(moved.tx).toBe(-500);
  });

  it("pans only when zoomed in", () => {
    expect(panView(homeView, stage, 50, 50)).toEqual(homeView);
    const zoomed = { s: 2, tx: -400, ty: -200 };
    expect(panView(zoomed, stage, 100, 0).tx).toBe(-300);
    expect(panView(zoomed, stage, 900, 0).tx).toBe(0);
  });
});

describe("fieldSize", () => {
  it("takes the stage width in a page", () => {
    expect(fieldSize(1000, 9999, 2, false)).toEqual({ w: 1000, h: 500 });
  });

  it("fits the stage when its height is fixed", () => {
    expect(fieldSize(1000, 300, 2, true)).toEqual({ w: 600, h: 300 });
    expect(fieldSize(400, 900, 2, true)).toEqual({ w: 400, h: 200 });
  });
});
