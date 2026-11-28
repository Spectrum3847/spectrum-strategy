import { maxPracticeTeams } from "./list";
import {
  boardSides,
  type Label,
  type Marker,
  type Phase,
  type Point,
  perPhase,
  phases,
  type Session,
  type Stroke,
} from "./model";

export interface Snap {
  strokes: Stroke[];
  markers: Marker[];
  labels: Label[];
  note?: string;
}

export interface History {
  undo: Record<Phase, Snap[]>;
  redo: Record<Phase, Snap[]>;
}

export interface Board {
  session: Session;
  history: History;
}

export interface Robot {
  team: number;
  side: "red" | "blue";
}

export type Hit =
  | { kind: "stroke"; item: Stroke }
  | { kind: "marker"; item: Marker }
  | { kind: "label"; item: Label };

export const maxUndo = 50;

export const emptyHistory = (): History => ({
  undo: perPhase(() => []),
  redo: perPhase(() => []),
});

const snapOf = (s: Session, p: Phase, withNote: boolean): Snap => ({
  strokes: s.strokes[p],
  markers: s.markers[p],
  labels: s.labels[p],
  ...(withNote ? { note: s.notes[p] } : {}),
});

function record(b: Board, p: Phase, withNote = false): History {
  const undo = [...b.history.undo[p], snapOf(b.session, p, withNote)].slice(
    -maxUndo,
  );
  return {
    undo: { ...b.history.undo, [p]: undo },
    redo: { ...b.history.redo, [p]: [] },
  };
}

function stamped(s: Session, now: number): Session {
  return { ...s, updatedMs: Math.max(now, s.updatedMs) };
}

function setPhase(
  s: Session,
  p: Phase,
  parts: Partial<Snap>,
  now: number,
): Session {
  return {
    ...stamped(s, now),
    strokes: parts.strokes ? { ...s.strokes, [p]: parts.strokes } : s.strokes,
    markers: parts.markers ? { ...s.markers, [p]: parts.markers } : s.markers,
    labels: parts.labels ? { ...s.labels, [p]: parts.labels } : s.labels,
    notes: parts.note !== undefined ? { ...s.notes, [p]: parts.note } : s.notes,
  };
}

function change(
  b: Board,
  p: Phase,
  parts: Partial<Snap>,
  now: number,
  history: History = record(b, p),
): Board {
  return { session: setPhase(b.session, p, parts, now), history };
}

export const teamsPlaced = (s: Session, p: Phase): Set<number> =>
  new Set(s.markers[p].flatMap((m) => (m.team === null ? [] : [m.team])));

export function addStroke(
  b: Board,
  p: Phase,
  stroke: Stroke,
  now: number,
): Board {
  return change(b, p, { strokes: [...b.session.strokes[p], stroke] }, now);
}

export function placeMarker(
  b: Board,
  p: Phase,
  marker: Marker,
  now: number,
): Board {
  if (marker.team !== null && teamsPlaced(b.session, p).has(marker.team)) {
    return b;
  }
  return change(b, p, { markers: [...b.session.markers[p], marker] }, now);
}

export function moveMarker(
  b: Board,
  p: Phase,
  marker: Marker,
  to: Point,
  now: number,
): Board {
  const list = b.session.markers[p];
  if (!list.includes(marker)) return b;
  return change(
    b,
    p,
    { markers: list.map((m) => (m === marker ? { ...m, position: to } : m)) },
    now,
  );
}

export function placeLabel(
  b: Board,
  p: Phase,
  label: Label,
  now: number,
): Board {
  return change(b, p, { labels: [...b.session.labels[p], label] }, now);
}

export function updateLabel(
  b: Board,
  p: Phase,
  label: Label,
  updated: Label,
  now: number,
): Board {
  const labels = b.session.labels[p];
  if (
    !labels.includes(label) ||
    (label.x === updated.x &&
      label.y === updated.y &&
      label.text === updated.text)
  )
    return b;
  return change(
    b,
    p,
    { labels: labels.map((item) => (item === label ? updated : item)) },
    now,
  );
}

export function erase(
  b: Board,
  p: Phase,
  hit: Hit,
  fresh: boolean,
  now: number,
): Board {
  const history = fresh ? record(b, p) : b.history;
  if (hit.kind === "label") {
    const labels = b.session.labels[p];
    if (!labels.includes(hit.item)) return b;
    return change(
      b,
      p,
      { labels: labels.filter((item) => item !== hit.item) },
      now,
      history,
    );
  }
  if (hit.kind === "marker") {
    const list = b.session.markers[p];
    if (!list.includes(hit.item)) return b;
    return change(
      b,
      p,
      { markers: list.filter((m) => m !== hit.item) },
      now,
      history,
    );
  }
  const list = b.session.strokes[p];
  if (!list.includes(hit.item)) return b;
  return change(
    b,
    p,
    { strokes: list.filter((s) => s !== hit.item) },
    now,
    history,
  );
}

export function clearPhase(b: Board, p: Phase, now: number): Board {
  return change(
    b,
    p,
    { strokes: [], markers: [], labels: [], note: "" },
    now,
    record(b, p, true),
  );
}

export function clearAll(b: Board, now: number): Board {
  return phases.reduce((board, p) => clearPhase(board, p, now), b);
}

export function placeAll(
  b: Board,
  p: Phase,
  robots: Robot[],
  now: number,
): Board {
  const rows = [0.2, 0.5, 0.8];
  const count = { red: 0, blue: 0 };
  const markers: Marker[] = robots.map((r) => {
    const row = rows[count[r.side]++ % rows.length] ?? 0.5;
    return {
      phase: p,
      position: { x: r.side === "red" ? 0.125 : 0.875, y: row },
      team: r.team,
      label: null,
      alliance: r.side === "red" ? "Red" : "Blue",
    };
  });
  return change(b, p, { markers }, now);
}

export function canMoveSide(s: Session, team: number): boolean {
  if (!s.teamNumbers.includes(team)) return false;
  const opponents = s.opponentTeams.length;
  const ours = s.teamNumbers.filter((n) => !s.opponentTeams.includes(n)).length;
  return (s.opponentTeams.includes(team) ? ours : opponents) < maxPracticeTeams;
}

export function moveTeamSide(b: Board, team: number, now: number): Board {
  if (!canMoveSide(b.session, team)) return b;
  const { opponentTeams } = b.session;
  const session = {
    ...stamped(b.session, now),
    opponentTeams: opponentTeams.includes(team)
      ? opponentTeams.filter((n) => n !== team)
      : [...opponentTeams, team].sort((a, c) => a - c),
  };
  const alliance = boardSides(session).red.includes(team) ? "Red" : "Blue";
  const markers = perPhase<Marker[]>(() => []);
  for (const p of phases) {
    markers[p] = session.markers[p].map((m) =>
      m.team === team ? { ...m, alliance } : m,
    );
  }
  return { ...b, session: { ...session, markers } };
}

export function setNote(b: Board, p: Phase, note: string, now: number): Board {
  return change(b, p, { note }, now, b.history);
}

export const canUndo = (h: History, p: Phase) => h.undo[p].length > 0;
export const canRedo = (h: History, p: Phase) => h.redo[p].length > 0;

function restore(
  b: Board,
  p: Phase,
  from: "undo" | "redo",
  now: number,
): Board {
  const stack = b.history[from][p];
  const step = stack.at(-1);
  if (!step) return b;
  const to = from === "undo" ? "redo" : "undo";
  const other = [
    ...b.history[to][p],
    snapOf(b.session, p, step.note !== undefined),
  ];
  return {
    session: setPhase(b.session, p, step, now),
    history: {
      ...b.history,
      [from]: { ...b.history[from], [p]: stack.slice(0, -1) },
      [to]: { ...b.history[to], [p]: other },
    },
  };
}

export const undo = (b: Board, p: Phase, now: number) =>
  restore(b, p, "undo", now);
export const redo = (b: Board, p: Phase, now: number) =>
  restore(b, p, "redo", now);
