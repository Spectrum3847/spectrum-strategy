import type { Hit } from "./edit";
import type { Marker, Point, Stroke } from "./model";

export interface Size {
  w: number;
  h: number;
}

export const strokeWidth = 4;
const arrowSpacing = 56;
const arrowLength = 7;
const arrowHalfAngle = 0.45;
const lightnessRange = 0.42;
const maxLightness = 0.78;
const bandCount = 16;

export const markerHit = 22;
const strokeHit = 16;
const minStep = 1.5;

const round4 = (n: number) => Math.round(n * 1e4) / 1e4;

export function argbToHsl(argb: number): { h: number; s: number; l: number } {
  const r = ((argb >> 16) & 255) / 255;
  const g = ((argb >> 8) & 255) / 255;
  const b = (argb & 255) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const l = (max + min) / 2;
  const d = max - min;
  if (d === 0) return { h: 0, s: 0, l };
  const s = d / (1 - Math.abs(2 * l - 1));
  const h =
    max === r
      ? ((g - b) / d + (g < b ? 6 : 0)) * 60
      : max === g
        ? ((b - r) / d + 2) * 60
        : ((r - g) / d + 4) * 60;
  return { h, s, l };
}

export function directionColor(argb: number, t: number): string {
  const { h, s, l } = argbToHsl(argb);
  const end = Math.min(maxLightness, l + lightnessRange);
  const at = Math.min(1, Math.max(0, t));
  const lightness = l + (end - l) * at;
  return `hsl(${h.toFixed(1)} ${(s * 100).toFixed(1)}% ${(lightness * 100).toFixed(1)}%)`;
}

export interface Band {
  points: string;
  color: string;
}

export interface Arrow {
  d: string;
  color: string;
}

export function strokeParts(
  points: Point[],
  color: number,
  size: Size,
): { bands: Band[]; arrows: Arrow[] } {
  const xy = points.map((p) => ({ x: p.x * size.w, y: p.y * size.h }));
  const lengths: number[] = [];
  let total = 0;
  for (let i = 1; i < xy.length; i++) {
    const a = xy[i - 1];
    const b = xy[i];
    const len = a && b ? Math.hypot(b.x - a.x, b.y - a.y) : 0;
    lengths.push(len);
    total += len;
  }
  if (total <= 0) return { bands: [], arrows: [] };

  const bands: Band[] = [];
  const arrows: Arrow[] = [];
  let band = -1;
  let current: string[] = [];
  let travelled = 0;
  let nextArrow = arrowSpacing;
  for (let i = 1; i < xy.length; i++) {
    const from = xy[i - 1];
    const to = xy[i];
    if (!from || !to) continue;
    const len = lengths[i - 1] ?? 0;
    const t = Math.min(1, (travelled + len / 2) / total);
    const k = Math.min(bandCount - 1, Math.floor(t * bandCount));
    if (k !== band) {
      if (current.length > 0) {
        bands.push({
          points: current.join(" "),
          color: directionColor(color, (band + 0.5) / bandCount),
        });
      }
      band = k;
      current = [`${from.x.toFixed(1)},${from.y.toFixed(1)}`];
    }
    current.push(`${to.x.toFixed(1)},${to.y.toFixed(1)}`);
    travelled += len;
    while (travelled >= nextArrow && total - nextArrow > arrowSpacing / 2) {
      if (len > 0) arrows.push(chevron(from, to, directionColor(color, t)));
      nextArrow += arrowSpacing;
    }
  }
  if (current.length > 0) {
    bands.push({
      points: current.join(" "),
      color: directionColor(color, (band + 0.5) / bandCount),
    });
  }
  return { bands, arrows };
}

function chevron(from: Point, to: Point, color: string): Arrow {
  const angle = Math.atan2(to.y - from.y, to.x - from.x);
  const leg = (turn: number) =>
    `${(to.x - arrowLength * Math.cos(angle + turn)).toFixed(1)},${(to.y - arrowLength * Math.sin(angle + turn)).toFixed(1)}`;
  return {
    d: `M${leg(-arrowHalfAngle)} L${to.x.toFixed(1)},${to.y.toFixed(1)} L${leg(arrowHalfAngle)}`,
    color,
  };
}

export function distanceToSegment(
  px: number,
  py: number,
  ax: number,
  ay: number,
  bx: number,
  by: number,
): number {
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy;
  if (len2 === 0) return Math.hypot(px - ax, py - ay);
  const t = Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / len2));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

function strokeNear(
  points: Point[],
  px: number,
  py: number,
  size: Size,
  tol: number,
): boolean {
  const first = points[0];
  if (!first) return false;
  let prev = { x: first.x * size.w, y: first.y * size.h };
  if (points.length === 1) return Math.hypot(px - prev.x, py - prev.y) <= tol;
  for (const p of points.slice(1)) {
    const next = { x: p.x * size.w, y: p.y * size.h };
    if (distanceToSegment(px, py, prev.x, prev.y, next.x, next.y) <= tol) {
      return true;
    }
    prev = next;
  }
  return false;
}

export function findHit(
  strokes: Stroke[],
  markers: Marker[],
  px: number,
  py: number,
  size: Size,
  legend: boolean,
  scale: number,
): Hit | null {
  if (!legend) {
    const reach = markerHit / scale;
    for (let i = markers.length - 1; i >= 0; i--) {
      const m = markers[i];
      if (!m) continue;
      if (
        Math.abs(px - m.position.x * size.w) <= reach &&
        Math.abs(py - m.position.y * size.h) <= reach
      ) {
        return { kind: "marker", item: m };
      }
    }
  }
  for (let i = strokes.length - 1; i >= 0; i--) {
    const s = strokes[i];
    if (
      s &&
      s.legend === legend &&
      strokeNear(s.points, px, py, size, strokeHit / scale)
    ) {
      return { kind: "stroke", item: s };
    }
  }
  return null;
}

export function markerAt(
  markers: Marker[],
  px: number,
  py: number,
  size: Size,
  scale: number,
): Marker | null {
  const hit = findHit([], markers, px, py, size, false, scale);
  return hit?.kind === "marker" ? hit.item : null;
}

export function nextPoint(
  last: Point | undefined,
  at: Point,
  size: Size,
  scale: number,
): Point | null {
  const next = { x: round4(at.x), y: round4(at.y) };
  if (!last) return next;
  const moved = Math.hypot(
    (next.x - last.x) * size.w * scale,
    (next.y - last.y) * size.h * scale,
  );
  return moved < minStep ? null : next;
}

export const clamp01 = (n: number) => Math.min(1, Math.max(0, n));

export interface View {
  s: number;
  tx: number;
  ty: number;
}

export interface Stage {
  sw: number;
  sh: number;
  fw: number;
  fh: number;
}

export const homeView: View = { s: 1, tx: 0, ty: 0 };
export const maxScale = 6;

const offset = (st: Stage) => ({
  ox: (st.sw - st.fw) / 2,
  oy: (st.sh - st.fh) / 2,
});

function clampAxis(t: number, stage: number, field: number, o: number): number {
  if (field <= stage) return (stage - field) / 2 - o;
  return Math.min(0 - o, Math.max(stage - field - o, t));
}

export function clampView(v: View, st: Stage): View {
  const s = Math.min(maxScale, Math.max(1, v.s));
  const { ox, oy } = offset(st);
  return {
    s,
    tx: clampAxis(v.tx, st.sw, st.fw * s, ox),
    ty: clampAxis(v.ty, st.sh, st.fh * s, oy),
  };
}

export function zoomAt(
  v: View,
  st: Stage,
  cx: number,
  cy: number,
  factor: number,
): View {
  const { ox, oy } = offset(st);
  const s = Math.min(maxScale, Math.max(1, v.s * factor));
  const px = (cx - ox - v.tx) / v.s;
  const py = (cy - oy - v.ty) / v.s;
  return clampView({ s, tx: cx - ox - px * s, ty: cy - oy - py * s }, st);
}

export function pinchView(
  start: View,
  st: Stage,
  from: { x: number; y: number; d: number },
  to: { x: number; y: number; d: number },
): View {
  const { ox, oy } = offset(st);
  const s = Math.min(
    maxScale,
    Math.max(1, from.d > 0 ? (start.s * to.d) / from.d : start.s),
  );
  const px = (from.x - ox - start.tx) / start.s;
  const py = (from.y - oy - start.ty) / start.s;
  return clampView({ s, tx: to.x - ox - px * s, ty: to.y - oy - py * s }, st);
}

export function panView(start: View, st: Stage, dx: number, dy: number): View {
  return clampView({ ...start, tx: start.tx + dx, ty: start.ty + dy }, st);
}

export function fieldSize(
  sw: number,
  sh: number,
  aspect: number,
  contain: boolean,
): Size {
  const w = contain ? Math.min(sw, sh * aspect) : sw;
  return { w, h: w / aspect };
}
