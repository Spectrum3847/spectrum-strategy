export const boardVersion = 1;

export const meetingRows = 13;
export const meetingColumns = 6;
export const extraRows = 10;
export const allianceRows = 8;
export const allianceColumns = 4;
export const maxCell = 24;
export const maxLabel = 24;

export const defaultLabels = [
  "Tier 1",
  "Tier 2",
  "Tier 3",
  "Tier 4",
  "Tier 5",
  "Tier 6",
];
export const allianceLabels = ["Captain", "Second", "Third", "Fourth"];

export type Grid = "meeting" | "alliance";

export interface CellStyle {
  highlighted: boolean;
  italic: boolean;
}

export interface PlayoffBoard {
  version: typeof boardVersion;
  labels: string[];
  meeting: Record<string, string>;
  styles: Record<string, CellStyle>;
  alliance: Record<string, string>;
}

export interface CellRef {
  grid: Grid;
  row: number;
  column: number;
}

export type Source =
  | ({ kind: "cell" } & CellRef)
  | { kind: "team"; team: number };

export const emptyBoard = (): PlayoffBoard => ({
  version: boardVersion,
  labels: [...defaultLabels],
  meeting: {},
  styles: {},
  alliance: {},
});

export const cellKey = (row: number, column: number) => `${row},${column}`;

export function isCell({ grid, row, column }: CellRef): boolean {
  if (!Number.isInteger(row) || !Number.isInteger(column)) return false;
  if (grid === "alliance") {
    return (
      row >= 0 && row < allianceRows && column >= 0 && column < allianceColumns
    );
  }
  if (column < 0 || column >= meetingColumns || row < 0) return false;
  if (row < meetingRows) return true;
  return row < meetingRows + extraRows && column === meetingColumns - 1;
}

const noStyle: CellStyle = { highlighted: false, italic: false };

export const styleOf = (board: PlayoffBoard, row: number, column: number) =>
  board.styles[cellKey(row, column)] ?? noStyle;

export const cellValue = (board: PlayoffBoard, ref: CellRef) =>
  (ref.grid === "meeting" ? board.meeting : board.alliance)[
    cellKey(ref.row, ref.column)
  ] ?? "";

const withEntry = <T>(
  map: Record<string, T>,
  key: string,
  value: T | null,
): Record<string, T> => {
  const next = { ...map };
  if (value === null) delete next[key];
  else next[key] = value;
  return next;
};

export function setCell(
  board: PlayoffBoard,
  ref: CellRef,
  text: string,
): PlayoffBoard {
  if (!isCell(ref)) return board;
  const value = text.slice(0, maxCell);
  const key = cellKey(ref.row, ref.column);
  const stored = value.trim() === "" ? null : value;
  return ref.grid === "meeting"
    ? { ...board, meeting: withEntry(board.meeting, key, stored) }
    : { ...board, alliance: withEntry(board.alliance, key, stored) };
}

export function setStyle(
  board: PlayoffBoard,
  row: number,
  column: number,
  style: CellStyle,
): PlayoffBoard {
  if (!isCell({ grid: "meeting", row, column })) return board;
  const plain = !style.highlighted && !style.italic;
  return {
    ...board,
    styles: withEntry(board.styles, cellKey(row, column), plain ? null : style),
  };
}

export function setLabel(
  board: PlayoffBoard,
  column: number,
  label: string,
): PlayoffBoard {
  if (column < 0 || column >= meetingColumns) return board;
  const labels = [...board.labels];
  labels[column] = label.slice(0, maxLabel);
  return { ...board, labels };
}

export const labelOf = (board: PlayoffBoard, column: number) =>
  board.labels[column] ?? defaultLabels[column] ?? "";

function swapCells(board: PlayoffBoard, a: CellRef, b: CellRef): PlayoffBoard {
  const first = cellValue(board, a);
  const second = cellValue(board, b);
  let next = setCell(setCell(board, a, second), b, first);
  const styleA =
    a.grid === "meeting" ? styleOf(board, a.row, a.column) : noStyle;
  const styleB =
    b.grid === "meeting" ? styleOf(board, b.row, b.column) : noStyle;
  if (a.grid === "meeting") next = setStyle(next, a.row, a.column, styleB);
  if (b.grid === "meeting") next = setStyle(next, b.row, b.column, styleA);
  return next;
}

export function move(
  board: PlayoffBoard,
  from: Source,
  to: CellRef,
): PlayoffBoard {
  if (!isCell(to)) return board;
  if (from.kind === "team") {
    return setCell(board, to, String(from.team));
  }
  if (!isCell(from)) return board;
  if (
    from.grid === to.grid &&
    from.row === to.row &&
    from.column === to.column
  ) {
    return board;
  }
  return swapCells(board, from, to);
}

export function clearCell(board: PlayoffBoard, ref: CellRef): PlayoffBoard {
  const next = setCell(board, ref, "");
  return ref.grid === "meeting"
    ? setStyle(next, ref.row, ref.column, noStyle)
    : next;
}

const teamOf = (text: string): number | null => {
  const trimmed = text.trim();
  return /^\d{1,5}$/.test(trimmed) ? Number(trimmed) : null;
};

export function readingOrder(board: PlayoffBoard): number[] {
  const out: number[] = [];
  const rows = meetingRows + extraRows;
  for (let row = 0; row < rows; row++) {
    for (let column = 0; column < meetingColumns; column++) {
      if (!isCell({ grid: "meeting", row, column })) continue;
      const team = teamOf(cellValue(board, { grid: "meeting", row, column }));
      if (team !== null) out.push(team);
    }
  }
  return out;
}

export function placed(board: PlayoffBoard): Set<number> {
  const out = new Set<number>();
  for (const text of Object.values(board.alliance)) {
    const team = teamOf(text);
    if (team !== null) out.add(team);
  }
  return out;
}

export const nextUpCount = 3;

export function nextUp(board: PlayoffBoard, count = nextUpCount): number[] {
  const taken = placed(board);
  const seen = new Set<number>();
  const out: number[] = [];
  for (const team of readingOrder(board)) {
    if (taken.has(team) || seen.has(team)) continue;
    seen.add(team);
    out.push(team);
    if (out.length === count) break;
  }
  return out;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);

function strings(
  raw: unknown,
  valid: (row: number, column: number) => boolean,
) {
  const out: Record<string, string> = {};
  if (!isRecord(raw)) return out;
  for (const [key, value] of Object.entries(raw)) {
    const m = /^(\d+),(\d+)$/.exec(key);
    if (!m || typeof value !== "string" || value.trim() === "") continue;
    if (valid(Number(m[1]), Number(m[2]))) out[key] = value.slice(0, maxCell);
  }
  return out;
}

export function parseBoard(raw: unknown): PlayoffBoard {
  if (!isRecord(raw)) return emptyBoard();
  const given = Array.isArray(raw.labels)
    ? raw.labels.filter((l): l is string => typeof l === "string")
    : [];
  const labels = defaultLabels.map((fallback, i) =>
    (given[i] ?? "").trim() === ""
      ? fallback
      : (given[i] ?? "").slice(0, maxLabel),
  );
  const styles: Record<string, CellStyle> = {};
  if (isRecord(raw.styles)) {
    for (const [key, value] of Object.entries(raw.styles)) {
      const m = /^(\d+),(\d+)$/.exec(key);
      if (!m || !isRecord(value)) continue;
      if (
        !isCell({ grid: "meeting", row: Number(m[1]), column: Number(m[2]) })
      ) {
        continue;
      }
      const style = {
        highlighted: value.highlighted === true,
        italic: value.italic === true,
      };
      if (style.highlighted || style.italic) styles[key] = style;
    }
  }
  return {
    version: boardVersion,
    labels,
    meeting: strings(raw.meeting, (row, column) =>
      isCell({ grid: "meeting", row, column }),
    ),
    styles,
    alliance: strings(raw.alliance, (row, column) =>
      isCell({ grid: "alliance", row, column }),
    ),
  };
}
