import {
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
  useId,
  useLayoutEffect,
  useRef,
  useState,
} from "react";
import { StrokeView } from "./Canvas";
import { bundled, fieldFor } from "./field";
import { clamp01, directionColor, nextPoint, strokeWidth } from "./geometry";
import {
  type Phase,
  type Point,
  penColor,
  phaseLabels,
  phases,
  type Stroke,
} from "./model";
import {
  emptySketch,
  eraseAt,
  isFull,
  maxStrokePoints,
  type Sketch,
  sketchIsEmpty,
  sketchLabel,
} from "./sketch";
import "./sketch.css";

const pen = directionColor(penColor, 0);
const field = fieldFor(bundled, "");
const aspect = field?.aspect ?? 2;
const fallbackWidth = 600;
const palmMs = 60_000;

function useWidth() {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const read = () => setWidth(el.clientWidth);
    read();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(read);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);
  return [ref, width > 0 ? width : fallbackWidth] as const;
}

const polyline = (points: Point[], w: number, h: number) =>
  points.map((p) => `${p.x * w},${p.y * h}`).join(" ");

interface SurfaceProps {
  strokes: Stroke[];
  label: string;
  phase: Phase;
  tool?: "draw" | "erase";
  locked?: boolean;
  onChange?(next: Stroke[]): void;
}

function Surface({
  strokes,
  label,
  phase,
  tool,
  locked,
  onChange,
}: SurfaceProps) {
  const [ref, w] = useWidth();
  const h = w / aspect;
  const [live, setLive] = useState<Point[]>([]);
  const gesture = useRef<{ id: number; points: Point[] } | null>(null);
  const current = useRef(strokes);
  current.current = strokes;
  const penAt = useRef(Number.NEGATIVE_INFINITY);
  const editable = tool !== undefined && onChange !== undefined;

  const toField = (e: { clientX: number; clientY: number }): Point | null => {
    const r = ref.current?.getBoundingClientRect();
    if (!r || r.width === 0 || r.height === 0) return null;
    return {
      x: clamp01((e.clientX - r.left) / r.width),
      y: clamp01((e.clientY - r.top) / r.height),
    };
  };

  const erase = (at: Point) => {
    const next = eraseAt(current.current, at.x * w, at.y * h, { w, h });
    if (next === current.current) return;
    current.current = next;
    onChange?.(next);
  };

  const onDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (!editable || gesture.current) return;
    if (e.pointerType === "mouse" && e.button !== 0) return;
    if (e.pointerType === "pen") penAt.current = e.timeStamp;
    if (e.pointerType === "touch" && e.timeStamp - penAt.current < palmMs) {
      return;
    }
    const at = toField(e);
    if (!at) return;
    if (tool === "draw" && locked) return;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    if (tool === "erase") {
      gesture.current = { id: e.pointerId, points: [] };
      erase(at);
      return;
    }
    const first = nextPoint(undefined, at, { w, h }, 1) ?? at;
    gesture.current = { id: e.pointerId, points: [first] };
    setLive([first]);
  };

  const onMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (!g || e.pointerId !== g.id) return;
    if (tool === "erase") {
      const at = toField(e);
      if (at) erase(at);
      return;
    }
    const events = e.nativeEvent.getCoalescedEvents?.() ?? [];
    for (const ev of events.length > 0 ? events : [e.nativeEvent]) {
      if (g.points.length >= maxStrokePoints) break;
      const at = toField(ev);
      const next = at && nextPoint(g.points.at(-1), at, { w, h }, 1);
      if (next) g.points.push(next);
    }
    setLive([...g.points]);
  };

  const finish = (e: ReactPointerEvent<HTMLDivElement>, commit: boolean) => {
    const g = gesture.current;
    if (!g || e.pointerId !== g.id) return;
    gesture.current = null;
    setLive([]);
    if (commit && tool === "draw" && g.points.length > 0) {
      onChange?.([
        ...current.current,
        { phase, legend: false, color: penColor, points: g.points },
      ]);
    }
  };

  return (
    // biome-ignore lint/a11y/useSemanticElements: a labelled drawing surface, not a form group
    <div
      ref={ref}
      className="sketch-stage"
      style={{ "--aspect": aspect } as CSSProperties}
      data-editable={editable}
      data-locked={locked === true}
      role="group"
      aria-label={label}
      onPointerDown={onDown}
      onPointerMove={onMove}
      onPointerUp={(e) => finish(e, true)}
      onPointerCancel={(e) => finish(e, false)}
    >
      {field && (
        <img
          className="sketch-img"
          src={field.image}
          alt=""
          draggable={false}
        />
      )}
      <svg
        className="sketch-svg"
        width={w}
        height={h}
        viewBox={`0 0 ${w} ${h}`}
        aria-hidden="true"
        focusable="false"
      >
        {strokes.map((s, i) =>
          s.points.length === 1 && s.points[0] ? (
            <circle
              // biome-ignore lint/suspicious/noArrayIndexKey: strokes have no id
              key={i}
              cx={s.points[0].x * w}
              cy={s.points[0].y * h}
              r={strokeWidth / 2}
              fill={pen}
            />
          ) : (
            <StrokeView
              // biome-ignore lint/suspicious/noArrayIndexKey: strokes have no id
              key={i}
              stroke={s}
              w={w}
              h={h}
            />
          ),
        )}
        {live.length > 0 && (
          <polyline
            points={polyline(live, w, h)}
            fill="none"
            stroke={pen}
            strokeWidth={strokeWidth}
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeOpacity={0.95}
          />
        )}
      </svg>
    </div>
  );
}

const hasPhase = (sketch: Sketch, phase: Phase) => sketch[phase].length > 0;

export function SketchEditor({
  title,
  surface,
  value,
  phased,
  onChange,
}: {
  title: string;
  surface: string;
  value: Sketch;
  phased: boolean;
  onChange(next: Sketch): void;
}) {
  const [phase, setPhase] = useState<Phase>("auton");
  const [tool, setTool] = useState<"draw" | "erase">("draw");
  const headingId = useId();
  const strokes = value[phase];
  const full = isFull(value, phase);
  return (
    <section className="sketch" aria-labelledby={headingId}>
      <h3 id={headingId} className="field-name">
        {title}
      </h3>
      {phased && (
        <fieldset className="chips sketch-bar">
          <legend className="sr-only">Phase</legend>
          {phases.map((p) => (
            <button
              key={p}
              type="button"
              className="chip"
              aria-pressed={p === phase}
              onClick={() => setPhase(p)}
            >
              {phaseLabels[p]}
              {hasPhase(value, p) && <span className="sr-only"> (drawn)</span>}
            </button>
          ))}
        </fieldset>
      )}
      <div className="chips sketch-bar">
        <button
          type="button"
          className="chip"
          aria-pressed={tool === "draw"}
          onClick={() => setTool("draw")}
        >
          Draw
        </button>
        <button
          type="button"
          className="chip"
          aria-pressed={tool === "erase"}
          onClick={() => setTool("erase")}
        >
          Erase
        </button>
        <button
          type="button"
          className="btn"
          disabled={sketchIsEmpty(value)}
          onClick={() => onChange(emptySketch())}
        >
          Clear
        </button>
      </div>
      <Surface
        strokes={strokes}
        label={sketchLabel(
          surface,
          phased ? phase : null,
          strokes.length,
          false,
        )}
        phase={phase}
        tool={tool}
        locked={full}
        onChange={(next) => onChange({ ...value, [phase]: next })}
      />
      {full && (
        <p className="secondary" role="status">
          The drawing is full. Erase a line to add more.
        </p>
      )}
    </section>
  );
}

export function SketchPreview({
  surface,
  value,
  phased,
}: {
  surface: string;
  value: Sketch;
  phased: boolean;
}) {
  const drawn = phases.filter((p) => hasPhase(value, p));
  const [picked, setPicked] = useState<Phase | null>(null);
  const phase = picked && drawn.includes(picked) ? picked : drawn[0];
  if (!phase) return null;
  const strokes = value[phase];
  return (
    <div className="sketch-preview">
      {phased && drawn.length > 1 && (
        <fieldset className="chips sketch-bar">
          <legend className="sr-only">Phase</legend>
          {drawn.map((p) => (
            <button
              key={p}
              type="button"
              className="chip"
              aria-pressed={p === phase}
              onClick={() => setPicked(p)}
            >
              {phaseLabels[p]}
            </button>
          ))}
        </fieldset>
      )}
      <Surface
        strokes={strokes}
        label={sketchLabel(
          surface,
          phased ? phase : null,
          strokes.length,
          true,
        )}
        phase={phase}
      />
    </div>
  );
}

export function SketchToggle({
  surface,
  value,
  phased,
}: {
  surface: string;
  value: Sketch;
  phased: boolean;
}) {
  if (sketchIsEmpty(value)) return null;
  return (
    <details className="sketch-toggle">
      <summary>Drawing</summary>
      <SketchPreview surface={surface} value={value} phased={phased} />
    </details>
  );
}
