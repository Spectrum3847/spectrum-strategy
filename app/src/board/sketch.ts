import { findHit, type Size } from "./geometry";
import {
  type Phase,
  parseStroke,
  perPhase,
  phaseLabels,
  phases,
  type Stroke,
  strokeJson,
} from "./model";

export type Sketch = Record<Phase, Stroke[]>;

export const maxStrokes = 300;
export const maxStrokePoints = 1500;
export const maxPoints = 8000;

export const emptySketch = (): Sketch => perPhase(() => []);

const isRecord = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

export function strokesFromList(raw: unknown): Stroke[] {
  return Array.isArray(raw) ? raw.flatMap((s) => parseStroke(s) ?? []) : [];
}

export function sketchFromJson(raw: unknown): Sketch {
  const sketch = emptySketch();
  if (!isRecord(raw)) return sketch;
  for (const phase of phases) sketch[phase] = strokesFromList(raw[phase]);
  return sketch;
}

export const strokesToJson = (strokes: Stroke[]) => strokes.map(strokeJson);

export function sketchToJson(sketch: Sketch): Record<string, unknown[]> | null {
  const out: Record<string, unknown[]> = {};
  for (const phase of phases) {
    if (sketch[phase].length > 0) out[phase] = strokesToJson(sketch[phase]);
  }
  return Object.keys(out).length > 0 ? out : null;
}

export const sketchIsEmpty = (sketch: Sketch) =>
  phases.every((p) => sketch[p].length === 0);

export const hasStrokes = (sketch: Sketch) => !sketchIsEmpty(sketch);

export function isFull(sketch: Sketch, phase: Phase): boolean {
  const points = phases.reduce(
    (n, p) => n + sketch[p].reduce((m, s) => m + s.points.length, 0),
    0,
  );
  return sketch[phase].length >= maxStrokes || points >= maxPoints;
}

export function eraseAt(
  strokes: Stroke[],
  px: number,
  py: number,
  size: Size,
): Stroke[] {
  const hit = findHit(strokes, [], px, py, size, false, 1);
  if (hit?.kind !== "stroke") return strokes;
  return strokes.filter((s) => s !== hit.item);
}

export function sketchLabel(
  surface: string,
  phase: Phase | null,
  strokes: number,
  readOnly: boolean,
): string {
  return [
    surface,
    phase ? `${phaseLabels[phase]} phase` : null,
    strokes === 0
      ? "empty"
      : `${strokes} ${strokes === 1 ? "drawing" : "drawings"}`,
    readOnly ? "read only" : null,
  ]
    .filter((p) => p !== null)
    .join(", ");
}
