import { Timestamp } from "firebase/firestore";

export const phases = ["auton", "teleop", "endgame"] as const;
export type Phase = (typeof phases)[number];

export const tools = ["draw", "robot", "text", "delete"] as const;
export type Tool = (typeof tools)[number];

export const phaseLabels: Record<Phase, string> = {
  auton: "Auto",
  teleop: "Teleop",
  endgame: "Endgame",
};

export const penColor = 0xff3c0060;

export interface Point {
  x: number;
  y: number;
}

export interface Stroke {
  phase: Phase;
  legend: boolean;
  color: number;
  points: Point[];
}

export interface Marker {
  phase: Phase;
  position: Point;
  team: number | null;
  label: string | null;
  alliance: string;
}

export interface Label extends Point {
  text: string;
}

export interface Session {
  id: string;
  eventKey: string;
  eventName: string;
  matchNumber: number;
  alliance: string;
  teamNumbers: number[];
  opponentTeams: number[];
  selectedPhase: Phase;
  selectedTool: Tool;
  selectedFieldId: string;
  selectedRobotTeam: number | null;
  updatedMs: number;
  authorUid: string;
  authorDisplayName: string;
  strokes: Record<Phase, Stroke[]>;
  markers: Record<Phase, Marker[]>;
  labels: Record<Phase, Label[]>;
  notes: Record<Phase, string>;
}

export interface Author {
  uid: string;
  displayName: string;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : null);
const int = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : null;
const phaseOf = (v: unknown): Phase | null =>
  phases.find((p) => p === v) ?? null;
const toolOf = (v: unknown): Tool | null => tools.find((t) => t === v) ?? null;

const sortedUnique = (list: number[]) =>
  [...new Set(list)].sort((a, b) => a - b);

export const perPhase = <T>(make: () => T): Record<Phase, T> => ({
  auton: make(),
  teleop: make(),
  endgame: make(),
});

export function newSession(input: {
  id: string;
  eventKey: string;
  matchNumber: number;
  alliance: string;
  teamNumbers: number[];
  opponentTeams?: number[];
  fieldId: string;
  author: Author;
  nowMs: number;
}): Session {
  const teamNumbers = sortedUnique(input.teamNumbers);
  return {
    id: input.id,
    eventKey: input.eventKey,
    eventName: "",
    matchNumber: input.matchNumber,
    alliance: input.alliance,
    teamNumbers,
    opponentTeams: sortedUnique(input.opponentTeams ?? []).filter((n) =>
      teamNumbers.includes(n),
    ),
    selectedPhase: "auton",
    selectedTool: "draw",
    selectedFieldId: input.fieldId,
    selectedRobotTeam: null,
    updatedMs: input.nowMs,
    authorUid: input.author.uid,
    authorDisplayName: input.author.displayName,
    strokes: perPhase(() => []),
    markers: perPhase(() => []),
    labels: perPhase(() => []),
    notes: perPhase(() => ""),
  };
}

function parsePoint(raw: unknown): Point | null {
  if (!isRecord(raw)) return null;
  const { x, y } = raw;
  return typeof x === "number" && typeof y === "number" ? { x, y } : null;
}

export function parseStroke(raw: unknown): Stroke | null {
  if (!isRecord(raw)) return null;
  const points: Point[] = [];
  if (Array.isArray(raw.points)) {
    for (const value of raw.points) {
      const point = parsePoint(value);
      if (point) points.push(point);
    }
  }
  return {
    phase: phaseOf(raw.phase) ?? "auton",
    legend: raw.isLegend === true,
    color: int(raw.colorValue) ?? penColor,
    points,
  };
}

function parseMarker(raw: unknown): Marker | null {
  if (!isRecord(raw)) return null;
  const position = parsePoint(raw.position);
  if (!position) return null;
  return {
    phase: phaseOf(raw.phase) ?? "auton",
    position,
    team: int(raw.teamNumber),
    label: str(raw.label),
    alliance: str(raw.alliance) ?? "Red",
  };
}

function parseLabel(raw: unknown): Label | null {
  const point = parsePoint(raw);
  if (!point || !isRecord(raw) || typeof raw.text !== "string") return null;
  if (
    !Number.isFinite(point.x) ||
    !Number.isFinite(point.y) ||
    point.x < 0 ||
    point.x > 1 ||
    point.y < 0 ||
    point.y > 1
  )
    return null;
  return { ...point, text: raw.text.slice(0, 60) };
}

function parsePhased<T>(
  raw: unknown,
  parse: (value: unknown) => T | null,
): Record<Phase, T[]> {
  const out = perPhase<T[]>(() => []);
  if (!isRecord(raw)) return out;
  for (const [key, list] of Object.entries(raw)) {
    const phase = phaseOf(key);
    if (phase === null || !Array.isArray(list)) continue;
    out[phase] = list.flatMap((value) => parse(value) ?? []);
  }
  return out;
}

export function parseSession(
  id: string,
  data: Raw,
  fallbackField: string,
): Session {
  const notes = perPhase(() => "");
  if (isRecord(data.notesByPhase)) {
    for (const [key, value] of Object.entries(data.notesByPhase)) {
      const phase = phaseOf(key);
      if (phase !== null) notes[phase] = str(value) ?? "";
    }
  }
  const parsed = Date.parse(str(data.updatedAt) ?? "");
  const fieldId = (str(data.selectedFieldId) ?? "").trim();
  const teamNumbers = Array.isArray(data.teamNumbers)
    ? data.teamNumbers.flatMap((n) => int(n) ?? [])
    : [];
  const opponentTeams = Array.isArray(data.opponentTeams)
    ? sortedUnique(data.opponentTeams.flatMap((n) => int(n) ?? [])).filter(
        (n) => teamNumbers.includes(n),
      )
    : [];
  return {
    id: (str(data.id) ?? "").trim() !== "" ? (str(data.id) as string) : id,
    eventKey: str(data.eventKey) ?? "",
    eventName: str(data.eventName) ?? "",
    matchNumber: int(data.matchNumber) ?? 1,
    alliance: str(data.alliance) ?? "Red",
    teamNumbers,
    opponentTeams,
    selectedPhase: phaseOf(data.selectedPhase) ?? "auton",
    selectedTool: toolOf(data.selectedTool) ?? "draw",
    selectedFieldId: fieldId !== "" ? fieldId : fallbackField,
    selectedRobotTeam: int(data.selectedRobotTeam),
    updatedMs:
      data.updatedAtTs instanceof Timestamp
        ? data.updatedAtTs.toMillis()
        : Number.isNaN(parsed)
          ? 0
          : parsed,
    authorUid: str(data.authorUid) ?? "",
    authorDisplayName: str(data.authorDisplayName) ?? "",
    strokes: parsePhased(data.strokesByPhase, parseStroke),
    markers: parsePhased(data.markersByPhase, parseMarker),
    labels: parsePhased(data.labelsByPhase, parseLabel),
    notes,
  };
}

export const strokeJson = (s: Stroke): Raw => ({
  phase: s.phase,
  ...(s.legend ? { isLegend: true } : {}),
  colorValue: s.color,
  points: s.points.map((p) => ({ x: p.x, y: p.y })),
});

const markerJson = (m: Marker): Raw => ({
  phase: m.phase,
  position: { x: m.position.x, y: m.position.y },
  teamNumber: m.team,
  label: m.label,
  alliance: m.alliance,
});

export function sessionJson(s: Session): Raw {
  const byPhase = <T>(map: Record<Phase, T>, each: (v: T) => unknown) =>
    Object.fromEntries(phases.map((p) => [p, each(map[p])]));
  return {
    id: s.id,
    ...(s.eventKey !== "" ? { eventKey: s.eventKey } : {}),
    eventName: s.eventName,
    matchNumber: s.matchNumber,
    alliance: s.alliance,
    teamNumbers: s.teamNumbers,
    ...(s.opponentTeams.length > 0 ? { opponentTeams: s.opponentTeams } : {}),
    selectedPhase: s.selectedPhase,
    selectedTool: s.selectedTool,
    selectedFieldId: s.selectedFieldId,
    selectedRobotTeam: s.selectedRobotTeam,
    updatedAt: new Date(s.updatedMs).toISOString(),
    ...(s.authorUid !== "" ? { authorUid: s.authorUid } : {}),
    ...(s.authorDisplayName !== ""
      ? { authorDisplayName: s.authorDisplayName }
      : {}),
    strokesByPhase: byPhase(s.strokes, (l) => l.map(strokeJson)),
    markersByPhase: byPhase(s.markers, (l) => l.map(markerJson)),
    labelsByPhase: byPhase(s.labels, (l) => l.map((label) => ({ ...label }))),
    notesByPhase: byPhase(s.notes, (n) => n),
  };
}

export function sessionDoc(s: Session, author: Author): Raw {
  return {
    ...sessionJson(s),
    authorUid: s.authorUid !== "" ? s.authorUid : author.uid,
    authorDisplayName:
      s.authorDisplayName !== ""
        ? s.authorDisplayName
        : author.displayName.slice(0, 128),
    updatedAtTs: Timestamp.fromMillis(s.updatedMs),
  };
}

export function boardSides(s: Session): { red: number[]; blue: number[] } {
  const ours = s.teamNumbers.filter((n) => !s.opponentTeams.includes(n));
  return s.alliance === "Blue"
    ? { red: s.opponentTeams, blue: ours }
    : { red: ours, blue: s.opponentTeams };
}

export function newest(boards: Session[]): Session | null {
  let best: Session | null = null;
  for (const board of boards) {
    if (!best || board.updatedMs > best.updatedMs) best = board;
  }
  return best;
}
