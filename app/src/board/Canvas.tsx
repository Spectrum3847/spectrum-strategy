import {
  type CSSProperties,
  memo,
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { BoardController, BoardState } from "./controller";
import type { Robot } from "./edit";
import type { Field } from "./field";
import {
  clamp01,
  clampView,
  directionColor,
  fieldSize,
  findHit,
  homeView,
  markerAt,
  nextPoint,
  panView,
  pinchView,
  type Size,
  type Stage,
  strokeParts,
  strokeWidth,
  type View,
  zoomAt,
} from "./geometry";
import {
  CircleIcon,
  FitIcon,
  SquareIcon,
  TriangleIcon,
  ZoomInIcon,
  ZoomOutIcon,
} from "./icons";
import {
  type Label,
  type Marker,
  type Phase,
  type Point,
  penColor,
  phaseLabels,
  type Stroke,
} from "./model";

const pen = directionColor(penColor, 0);
const legendHeight = 64;
const nudge = 0.01;

export const StrokeView = memo(function StrokeView({
  stroke,
  w,
  h,
}: {
  stroke: Stroke;
  w: number;
  h: number;
}) {
  const parts = useMemo(
    () => strokeParts(stroke.points, stroke.color, { w, h }),
    [stroke, w, h],
  );
  return (
    <g fill="none" strokeLinecap="round" strokeLinejoin="round">
      {parts.bands.map((band, i) => (
        <polyline
          // biome-ignore lint/suspicious/noArrayIndexKey: bands are positional
          key={i}
          points={band.points}
          stroke={band.color}
          strokeWidth={strokeWidth}
          strokeOpacity={0.95}
        />
      ))}
      {parts.arrows.map((arrow, i) => (
        <path
          // biome-ignore lint/suspicious/noArrayIndexKey: arrows are positional
          key={i}
          d={arrow.d}
          stroke={arrow.color}
          strokeWidth={2.5}
        />
      ))}
    </g>
  );
});

type Anchor = { x: number; y: number; d: number };

type Gesture =
  | { mode: "none" }
  | { mode: "stroke"; id: number; points: Point[] }
  | { mode: "erase"; id: number; fresh: boolean }
  | { mode: "marker"; id: number; marker: Marker }
  | { mode: "label"; id: number; label: Label; start: Point; moved: boolean }
  | { mode: "nav"; base: View; from: Anchor };

function anchorOf(touches: Map<number, { x: number; y: number }>): Anchor {
  const [a, b] = [...touches.values()];
  if (!a) return { x: 0, y: 0, d: 0 };
  if (!b) return { x: a.x, y: a.y, d: 0 };
  return {
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
    d: Math.hypot(b.x - a.x, b.y - a.y),
  };
}

export const boardLabel = (
  phase: Phase,
  strokes: number,
  markers: number,
  labels = 0,
): string => {
  const parts = [`Strategy board, ${phaseLabels[phase]} phase`];
  if (strokes === 0 && markers === 0 && labels === 0) parts.push("empty");
  if (strokes > 0)
    parts.push(`${strokes} ${strokes === 1 ? "drawing" : "drawings"}`);
  if (markers > 0)
    parts.push(`${markers} ${markers === 1 ? "robot" : "robots"}`);
  if (labels > 0) parts.push(`${labels} ${labels === 1 ? "label" : "labels"}`);
  return parts.join(", ");
};

interface Props {
  field: Field;
  state: BoardState;
  robots: Robot[];
  controller: BoardController;
  full: boolean;
  describedBy: string;
}

export function BoardCanvas({
  field,
  state,
  robots,
  controller,
  full,
  describedBy,
}: Props) {
  const stageRef = useRef<HTMLDivElement>(null);
  const fieldRef = useRef<HTMLDivElement>(null);
  const activeRef = useRef<SVGPolylineElement>(null);
  const [box, setBox] = useState({ sw: 0, sh: 0 });
  const [view, setView] = useState<View>(homeView);
  const [drag, setDrag] = useState<{ marker: Marker; at: Point } | null>(null);

  const [labelDrag, setLabelDrag] = useState<{
    label: Label;
    at: Point;
  } | null>(null);
  const [editing, setEditing] = useState<{
    label: Label | null;
    at: Point;
    text: string;
  } | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  useEffect(() => {
    if (editing) inputRef.current?.focus();
  }, [editing]);
  // biome-ignore lint/correctness/useExhaustiveDependencies: phase changes cancel the active input
  useEffect(() => {
    setEditing(null);
    controller.setDrawing(false);
  }, [state.phase, controller]);

  const size = fieldSize(box.sw, box.sh, field.aspect, full);
  const stage: Stage = { sw: box.sw, sh: box.sh, fw: size.w, fh: size.h };
  const live = useRef({ view, size, stage });
  live.current = { view, size, stage };

  useEffect(() => {
    const el = stageRef.current;
    if (!el) return;
    const read = () => setBox({ sw: el.clientWidth, sh: el.clientHeight });
    read();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(read);
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // biome-ignore lint/correctness/useExhaustiveDependencies: the stage numbers are the trigger
  useEffect(() => {
    setView((v) => clampView(v, live.current.stage));
  }, [box.sw, box.sh, size.w, size.h]);

  const gesture = useRef<Gesture>({ mode: "none" });
  const touches = useRef(new Map<number, { x: number; y: number }>());
  const penAt = useRef(Number.NEGATIVE_INFINITY);
  const frame = useRef(0);
  useEffect(() => () => cancelAnimationFrame(frame.current), []);

  const paintActive = (points: Point[]) => {
    if (frame.current) return;
    frame.current = requestAnimationFrame(() => {
      frame.current = 0;
      const { w, h } = live.current.size;
      activeRef.current?.setAttribute(
        "points",
        points.map((p) => `${p.x * w},${p.y * h}`).join(" "),
      );
    });
  };

  const clearActive = () => {
    if (frame.current) cancelAnimationFrame(frame.current);
    frame.current = 0;
    activeRef.current?.setAttribute("points", "");
  };

  const toField = (clientX: number, clientY: number) => {
    const r = fieldRef.current?.getBoundingClientRect();
    if (!r || r.width === 0 || r.height === 0) return null;
    const n = {
      x: clamp01((clientX - r.left) / r.width),
      y: clamp01((clientY - r.top) / r.height),
    };
    const { w, h } = live.current.size;
    return { n, px: n.x * w, py: n.y * h };
  };

  const stagePoint = (e: { clientX: number; clientY: number }) => {
    const r = stageRef.current?.getBoundingClientRect();
    return { x: e.clientX - (r?.left ?? 0), y: e.clientY - (r?.top ?? 0) };
  };

  const labelEls = useRef(new Map<HTMLElement, Label>());
  const labelAt = (clientX: number, clientY: number): Label | null => {
    for (const [el, label] of Array.from(labelEls.current).reverse()) {
      const r = el.getBoundingClientRect();
      if (
        clientX >= r.left &&
        clientX <= r.right &&
        clientY >= r.top &&
        clientY <= r.bottom
      )
        return label;
    }
    return null;
  };

  const eraseAt = (
    px: number,
    py: number,
    g: { fresh: boolean },
    clientX: number,
    clientY: number,
  ) => {
    const label = labelAt(clientX, clientY);
    if (label) {
      controller.erase({ kind: "label", item: label }, g.fresh);
      g.fresh = false;
      return;
    }
    const s = controller.getSnapshot();
    const hit = findHit(
      s.session.strokes[s.phase],
      s.session.markers[s.phase],
      px,
      py,
      live.current.size,
      false,
      live.current.view.s,
    );
    if (hit) {
      controller.erase(hit, g.fresh);
      g.fresh = false;
    }
  };

  const startNav = () => {
    gesture.current = {
      mode: "nav",
      base: live.current.view,
      from: anchorOf(touches.current),
    };
  };

  const end = (keepDrawing = false) => {
    gesture.current = { mode: "none" };
    clearActive();
    setDrag(null);
    setLabelDrag(null);
    if (!keepDrawing) controller.setDrawing(false);
  };

  const onDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.pointerType === "mouse" && e.button !== 0) return;
    if (e.pointerType === "pen") penAt.current = e.timeStamp;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    if (e.pointerType === "touch") {
      touches.current.set(e.pointerId, stagePoint(e));
      if (touches.current.size >= 2) {
        if (gesture.current.mode !== "nav") end();
        startNav();
        return;
      }
      if (e.timeStamp - penAt.current < 60_000) {
        startNav();
        return;
      }
    }
    if (gesture.current.mode !== "none") return;
    const at = toField(e.clientX, e.clientY);
    if (!at) return;
    const tool = controller.getSnapshot().tool;
    if (tool === "draw") {
      const first =
        nextPoint(undefined, at.n, live.current.size, live.current.view.s) ??
        at.n;
      gesture.current = { mode: "stroke", id: e.pointerId, points: [first] };
      controller.setDrawing(true);
    } else if (tool === "text") {
      const label = labelAt(e.clientX, e.clientY);
      if (label) {
        gesture.current = {
          mode: "label",
          id: e.pointerId,
          label,
          start: { x: e.clientX, y: e.clientY },
          moved: false,
        };
        controller.setDrawing(true);
      } else {
        e.preventDefault();
        setEditing({ label: null, at: at.n, text: "" });
        controller.setDrawing(true);
      }
    } else if (tool === "robot") {
      const s = controller.getSnapshot();
      const marker = markerAt(
        s.session.markers[s.phase],
        at.px,
        at.py,
        live.current.size,
        live.current.view.s,
      );
      if (marker) {
        gesture.current = { mode: "marker", id: e.pointerId, marker };
        setDrag({ marker, at: marker.position });
        controller.setDrawing(true);
      } else {
        controller.placeAt(at.n);
      }
    } else {
      const g = { mode: "erase" as const, id: e.pointerId, fresh: true };
      gesture.current = g;
      controller.setDrawing(true);
      eraseAt(at.px, at.py, g, e.clientX, e.clientY);
    }
  };

  const onMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (touches.current.has(e.pointerId)) {
      touches.current.set(e.pointerId, stagePoint(e));
    }
    if (g.mode === "nav") {
      const to = anchorOf(touches.current);
      const { stage: st } = live.current;
      setView(
        touches.current.size >= 2
          ? pinchView(g.base, st, g.from, to)
          : panView(g.base, st, to.x - g.from.x, to.y - g.from.y),
      );
      return;
    }
    if (g.mode === "none" || e.pointerId !== g.id) return;
    if (g.mode === "stroke") {
      const coalesced = e.nativeEvent.getCoalescedEvents?.() ?? [];
      for (const ev of coalesced.length > 0 ? coalesced : [e.nativeEvent]) {
        const at = toField(ev.clientX, ev.clientY);
        if (!at) continue;
        const next = nextPoint(
          g.points.at(-1),
          at.n,
          live.current.size,
          live.current.view.s,
        );
        if (next) g.points.push(next);
      }
      paintActive(g.points);
    } else if (g.mode === "erase") {
      const at = toField(e.clientX, e.clientY);
      if (at) eraseAt(at.px, at.py, g, e.clientX, e.clientY);
    } else if (g.mode === "label") {
      if (Math.hypot(e.clientX - g.start.x, e.clientY - g.start.y) >= 4)
        g.moved = true;
      const at = toField(e.clientX, e.clientY);
      if (g.moved && at) setLabelDrag({ label: g.label, at: at.n });
    } else {
      const at = toField(e.clientX, e.clientY);
      if (at) setDrag({ marker: g.marker, at: at.n });
    }
  };

  const onUp = (e: ReactPointerEvent<HTMLDivElement>, cancelled: boolean) => {
    touches.current.delete(e.pointerId);
    const g = gesture.current;
    if (g.mode === "nav") {
      if (touches.current.size > 0) {
        startNav();
        return;
      }
      end();
      return;
    }
    if (g.mode === "none" || e.pointerId !== g.id) return;
    if (!cancelled) {
      if (g.mode === "stroke") {
        controller.commitStroke(g.points, false);
      } else if (g.mode === "label") {
        const at = toField(e.clientX, e.clientY);
        if (g.moved && at)
          controller.updateLabel(g.label, { ...g.label, ...at.n });
        else setEditing({ label: g.label, at: g.label, text: g.label.text });
      } else if (g.mode === "marker") {
        const at = toField(e.clientX, e.clientY);
        if (at) controller.moveMarker(g.marker, at.n);
      }
    }
    end(!cancelled && g.mode === "label" && !g.moved);
  };

  // biome-ignore lint/correctness/useExhaustiveDependencies: stagePoint reads refs only
  useEffect(() => {
    const el = stageRef.current;
    if (!el) return;
    const wheel = (e: WheelEvent) => {
      if (!e.ctrlKey && !e.metaKey) return;
      e.preventDefault();
      const p = stagePoint(e);
      setView((v) =>
        zoomAt(v, live.current.stage, p.x, p.y, Math.exp(-e.deltaY * 0.01)),
      );
    };
    el.addEventListener("wheel", wheel, { passive: false });
    return () => el.removeEventListener("wheel", wheel);
  }, []);

  const zoomBy = (factor: number) =>
    setView((v) => zoomAt(v, stage, stage.sw / 2, stage.sh / 2, factor));

  const strokes = state.session.strokes[state.phase];
  const markers = state.session.markers[state.phase];
  const labels = state.session.labels[state.phase];
  const drawn = strokes.filter((s) => !s.legend);
  const ox = (stage.sw - size.w) / 2;
  const oy = (stage.sh - size.h) / 2;
  const sideOf = (m: Marker) =>
    robots.find((r) => r.team === m.team)?.side ??
    (m.alliance === "Blue" ? "blue" : "red");

  const moveWithKey = (m: Marker, e: ReactKeyboardEvent) => {
    const step = e.shiftKey ? nudge * 5 : nudge;
    const by = {
      ArrowLeft: [-step, 0],
      ArrowRight: [step, 0],
      ArrowUp: [0, -step],
      ArrowDown: [0, step],
    }[e.key];
    if (by) {
      e.preventDefault();
      controller.moveMarker(m, {
        x: clamp01(m.position.x + (by[0] ?? 0)),
        y: clamp01(m.position.y + (by[1] ?? 0)),
      });
    } else if (e.key === "Delete" || e.key === "Backspace") {
      e.preventDefault();
      controller.erase({ kind: "marker", item: m }, true);
    }
  };

  const finishLabel = (save: boolean) => {
    if (!editing) return;
    const text = editing.text.trim();
    if (save && text) {
      if (editing.label)
        controller.updateLabel(editing.label, { ...editing.label, text });
      else controller.placeLabel({ ...editing.at, text });
    } else if (save && editing.label)
      controller.erase({ kind: "label", item: editing.label }, true);
    setEditing(null);
    controller.setDrawing(false);
  };

  return (
    <div className="board-canvas">
      <Legend
        strokes={strokes}
        width={size.w}
        tool={state.tool}
        controller={controller}
      />
      {/* biome-ignore lint/a11y/useSemanticElements: a labelled drawing surface, not a form group */}
      <div
        ref={stageRef}
        className="board-stage"
        style={{ "--aspect": field.aspect } as CSSProperties}
        data-tool={state.tool}
        role="group"
        aria-label={boardLabel(
          state.phase,
          drawn.length,
          markers.length,
          labels.length,
        )}
        aria-describedby={describedBy}
        onPointerDown={onDown}
        onPointerMove={onMove}
        onPointerUp={(e) => onUp(e, false)}
        onPointerCancel={(e) => onUp(e, true)}
      >
        {size.w > 0 && (
          <div
            ref={fieldRef}
            className="board-field"
            style={{
              left: ox,
              top: oy,
              width: size.w,
              height: size.h,
              transform: `translate(${view.tx}px, ${view.ty}px) scale(${view.s})`,
            }}
          >
            <img
              className="board-img"
              src={field.image}
              alt=""
              draggable={false}
            />
            <svg
              className="board-svg"
              width={size.w}
              height={size.h}
              viewBox={`0 0 ${size.w} ${size.h}`}
              aria-hidden="true"
              focusable="false"
            >
              <Grid size={size} />
              {drawn.map((s, i) => (
                <StrokeView
                  // biome-ignore lint/suspicious/noArrayIndexKey: strokes have no id
                  key={i}
                  stroke={s}
                  w={size.w}
                  h={size.h}
                />
              ))}
              <polyline
                ref={activeRef}
                points=""
                fill="none"
                stroke={pen}
                strokeWidth={strokeWidth}
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeOpacity={0.95}
              />
            </svg>
            {labels.map((label, i) => {
              if (editing?.label === label) return null;
              const at = labelDrag?.label === label ? labelDrag.at : label;
              return (
                <button
                  // biome-ignore lint/suspicious/noArrayIndexKey: labels have no id
                  key={i}
                  type="button"
                  className="board-label"
                  ref={(el) => {
                    if (!el) return;
                    labelEls.current.set(el, label);
                    return () => {
                      labelEls.current.delete(el);
                    };
                  }}
                  aria-label={`${label.text}. Arrow keys move it, Delete removes it, Enter edits it.`}
                  style={
                    {
                      left: at.x * size.w,
                      top: at.y * size.h,
                      "--inv": 1 / view.s,
                    } as CSSProperties
                  }
                  onKeyDown={(e) => {
                    const step = e.shiftKey ? nudge * 5 : nudge;
                    const by = {
                      ArrowLeft: [-step, 0],
                      ArrowRight: [step, 0],
                      ArrowUp: [0, -step],
                      ArrowDown: [0, step],
                    }[e.key];
                    if (by) {
                      e.preventDefault();
                      controller.updateLabel(label, {
                        ...label,
                        x: clamp01(label.x + (by[0] ?? 0)),
                        y: clamp01(label.y + (by[1] ?? 0)),
                      });
                    } else if (e.key === "Delete" || e.key === "Backspace") {
                      e.preventDefault();
                      controller.erase({ kind: "label", item: label }, true);
                    } else if (e.key === "Enter") {
                      e.preventDefault();
                      controller.setDrawing(true);
                      setEditing({ label, at: label, text: label.text });
                    }
                  }}
                >
                  {label.text}
                </button>
              );
            })}
            {editing && (
              <input
                ref={inputRef}
                className="board-label board-label-input"
                aria-label="Label text"
                maxLength={60}
                value={editing.text}
                style={
                  {
                    left: editing.at.x * size.w,
                    top: editing.at.y * size.h,
                    "--inv": 1 / view.s,
                  } as CSSProperties
                }
                onPointerDown={(e) => e.stopPropagation()}
                onChange={(e) =>
                  setEditing({ ...editing, text: e.target.value })
                }
                onBlur={() => finishLabel(true)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === "Escape") {
                    e.preventDefault();
                    e.stopPropagation();
                    finishLabel(e.key === "Enter");
                  }
                }}
              />
            )}
            {markers.map((m, i) => {
              const at = drag?.marker === m ? drag.at : m.position;
              const side = sideOf(m);
              return (
                <button
                  // biome-ignore lint/suspicious/noArrayIndexKey: markers have no id
                  key={i}
                  type="button"
                  className="board-marker"
                  data-side={side}
                  aria-label={`${m.team === null ? "Robot" : `Team ${m.team}`}, ${side}. Arrow keys move it, Delete removes it.`}
                  style={
                    {
                      left: at.x * size.w,
                      top: at.y * size.h,
                      "--inv": 1 / view.s,
                    } as CSSProperties
                  }
                  onKeyDown={(e) => moveWithKey(m, e)}
                >
                  <span className="board-side" aria-hidden="true">
                    {side === "red" ? "R" : "B"}
                  </span>
                  {m.team === null ? "?" : m.team}
                </button>
              );
            })}
          </div>
        )}
        <fieldset
          className="board-zoom"
          onPointerDown={(e) => e.stopPropagation()}
        >
          <legend className="sr-only">Zoom</legend>
          <button
            type="button"
            className="board-tool"
            aria-label="Zoom in"
            disabled={view.s >= 6}
            onClick={() => zoomBy(1.5)}
          >
            <ZoomInIcon />
          </button>
          <button
            type="button"
            className="board-tool"
            aria-label="Zoom out"
            disabled={view.s <= 1}
            onClick={() => zoomBy(1 / 1.5)}
          >
            <ZoomOutIcon />
          </button>
          <button
            type="button"
            className="board-tool"
            aria-label="Reset zoom"
            disabled={view.s === 1 && view.tx === 0 && view.ty === 0}
            onClick={() => setView(homeView)}
          >
            <FitIcon />
          </button>
        </fieldset>
      </div>
    </div>
  );
}

function Grid({ size }: { size: Size }) {
  const lines = [0.25, 0.5, 0.75];
  return (
    <g strokeWidth={1}>
      {lines.map((f) => (
        <line
          key={`v${f}`}
          x1={size.w * f}
          x2={size.w * f}
          y1={0}
          y2={size.h}
          stroke={f === 0.5 ? "var(--accent)" : "var(--grid)"}
          strokeOpacity={f === 0.5 ? 0.35 : 0.6}
          strokeWidth={f === 0.5 ? 2 : 1}
        />
      ))}
      {[0.25, 0.5, 0.75].map((f) => (
        <line
          key={`h${f}`}
          x1={0}
          x2={size.w}
          y1={size.h * f}
          y2={size.h * f}
          stroke="var(--grid)"
          strokeOpacity={0.6}
        />
      ))}
    </g>
  );
}

function Legend({
  strokes,
  width,
  tool,
  controller,
}: {
  strokes: Stroke[];
  width: number;
  tool: BoardState["tool"];
  controller: BoardController;
}) {
  const activeRef = useRef<SVGPolylineElement>(null);
  const gesture = useRef<{
    id: number;
    points: Point[];
    fresh: boolean;
  } | null>(null);
  const w = width > 0 ? width : 0;
  const size: Size = { w, h: legendHeight };

  const at = (e: ReactPointerEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    if (r.width === 0) return null;
    return {
      x: clamp01((e.clientX - r.left) / r.width),
      y: clamp01((e.clientY - r.top) / r.height),
    };
  };

  const erase = (p: Point) => {
    const s = controller.getSnapshot();
    const hit = findHit(
      s.session.strokes[s.phase],
      [],
      p.x * size.w,
      p.y * size.h,
      size,
      true,
      1,
    );
    if (hit && gesture.current) {
      controller.erase(hit, gesture.current.fresh);
      gesture.current.fresh = false;
    }
  };

  const paint = (points: Point[]) =>
    activeRef.current?.setAttribute(
      "points",
      points.map((p) => `${p.x * size.w},${p.y * size.h}`).join(" "),
    );

  const finish = (commit: boolean) => {
    const g = gesture.current;
    gesture.current = null;
    paint([]);
    if (commit && g && tool === "draw") controller.commitStroke(g.points, true);
    controller.setDrawing(false);
  };

  const onDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (tool === "robot" || tool === "text" || gesture.current || w === 0)
      return;
    if (e.pointerType === "mouse" && e.button !== 0) return;
    const p = at(e);
    if (!p) return;
    e.currentTarget.setPointerCapture?.(e.pointerId);
    gesture.current = { id: e.pointerId, points: [p], fresh: true };
    controller.setDrawing(true);
    if (tool === "delete") erase(p);
    else paint([p]);
  };

  const onMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const g = gesture.current;
    if (!g || e.pointerId !== g.id) return;
    const p = at(e);
    if (!p) return;
    if (tool === "delete") {
      erase(p);
      return;
    }
    const next = nextPoint(g.points.at(-1), p, size, 1);
    if (next) g.points.push(next);
    paint(g.points);
  };

  const slots = [TriangleIcon, CircleIcon, SquareIcon];
  return (
    // biome-ignore lint/a11y/useSemanticElements: a labelled drawing surface, not a form group
    <div
      className="board-legend"
      style={{ width: w > 0 ? w : "100%", height: legendHeight }}
      role="group"
      aria-label="Opponent team numbers: triangle, circle, square. Write each number beside its shape."
      onPointerDown={onDown}
      onPointerMove={onMove}
      onPointerUp={(e) => {
        if (gesture.current?.id === e.pointerId) finish(true);
      }}
      onPointerCancel={(e) => {
        if (gesture.current?.id === e.pointerId) finish(false);
      }}
    >
      {slots.map((Shape, i) => (
        <div className="board-legend-slot" key={Shape.name || i}>
          <Shape />
          <span className="board-legend-rule" />
        </div>
      ))}
      <svg
        className="board-svg"
        width={w}
        height={legendHeight}
        viewBox={`0 0 ${w} ${legendHeight}`}
        aria-hidden="true"
        focusable="false"
      >
        {strokes
          .filter((s) => s.legend)
          .map((s, i) => {
            const first = s.points[0];
            return s.points.length === 1 && first ? (
              <circle
                // biome-ignore lint/suspicious/noArrayIndexKey: strokes have no id
                key={i}
                cx={first.x * w}
                cy={first.y * legendHeight}
                r={1.5}
                fill="var(--ink)"
              />
            ) : (
              <polyline
                // biome-ignore lint/suspicious/noArrayIndexKey: strokes have no id
                key={i}
                points={s.points
                  .map((p) => `${p.x * w},${p.y * legendHeight}`)
                  .join(" ")}
                fill="none"
                stroke="var(--ink)"
                strokeWidth={3}
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            );
          })}
        <polyline
          ref={activeRef}
          points=""
          fill="none"
          stroke="var(--ink)"
          strokeWidth={3}
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
}
