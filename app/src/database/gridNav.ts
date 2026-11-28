export interface Pos {
  row: number;
  col: number;
}

export interface Dims {
  rows: number;
  cols: number;
}

const clamp = (n: number, max: number) => Math.max(0, Math.min(n, max - 1));

export type Move = "up" | "down" | "left" | "right" | "home" | "end";

export function move(pos: Pos, to: Move, dims: Dims): Pos {
  const at = (row: number, col: number) => ({
    row: clamp(row, dims.rows),
    col: clamp(col, dims.cols),
  });
  switch (to) {
    case "up":
      return at(pos.row - 1, pos.col);
    case "down":
      return at(pos.row + 1, pos.col);
    case "left":
      return at(pos.row, pos.col - 1);
    case "right":
      return at(pos.row, pos.col + 1);
    case "home":
      return at(pos.row, 0);
    case "end":
      return at(pos.row, dims.cols - 1);
  }
}

export function tab(pos: Pos, back: boolean, dims: Dims): Pos {
  const index = pos.row * dims.cols + pos.col + (back ? -1 : 1);
  const last = dims.rows * dims.cols - 1;
  const i = Math.max(0, Math.min(index, last));
  return { row: Math.floor(i / dims.cols), col: i % dims.cols };
}

export const arrowMoves: Record<string, Move> = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
  Home: "home",
  End: "end",
};
