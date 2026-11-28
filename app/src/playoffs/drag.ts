import { type PointerEvent, useRef, useState } from "react";
import { type CellRef, isCell, type Source } from "./board";

export const cellAttr = (ref: CellRef) =>
  `${ref.grid}:${ref.row},${ref.column}`;

export function parseCellAttr(text: string): CellRef | null {
  const m = /^(meeting|alliance):(\d+),(\d+)$/.exec(text);
  if (!m) return null;
  const ref: CellRef = {
    grid: m[1] as CellRef["grid"],
    row: Number(m[2]),
    column: Number(m[3]),
  };
  return isCell(ref) ? ref : null;
}

function cellAt(x: number, y: number): CellRef | null {
  const el = document
    .elementFromPoint(x, y)
    ?.closest<HTMLElement>("[data-cell]");
  return el ? parseCellAttr(el.dataset.cell ?? "") : null;
}

const edge = 64;

export const sameCell = (a: CellRef | null, b: CellRef | null) =>
  a !== null &&
  b !== null &&
  a.grid === b.grid &&
  a.row === b.row &&
  a.column === b.column;

export type CellDrag = ReturnType<typeof useCellDrag>;

export function useCellDrag(onDrop: (from: Source, to: CellRef) => void) {
  const [dragging, setDragging] = useState<Source | null>(null);
  const [over, setOver] = useState<CellRef | null>(null);
  const last = useRef<CellRef | null>(null);
  const active = useRef<string | null>(null);
  const start = useRef({ x: 0, y: 0 });
  const dragged = useRef(false);

  const finish = () => {
    setDragging(null);
    setOver(null);
    last.current = null;
    active.current = null;
  };

  const handlers = (source: Source, id: string) => ({
    onPointerDown(e: PointerEvent<HTMLElement>) {
      if (e.button !== 0) return;
      e.currentTarget.setPointerCapture(e.pointerId);
      dragged.current = false;
      setDragging(source);
      last.current = null;
      active.current = id;
      start.current = { x: e.clientX, y: e.clientY };
    },
    onPointerMove(e: PointerEvent<HTMLElement>) {
      if (active.current !== id) return;
      if (
        Math.hypot(e.clientX - start.current.x, e.clientY - start.current.y) > 8
      ) {
        dragged.current = true;
      }
      if (e.clientY < edge) window.scrollBy(0, -12);
      else if (e.clientY > window.innerHeight - edge) window.scrollBy(0, 12);
      const next = cellAt(e.clientX, e.clientY);
      last.current = next;
      setOver(next);
    },
    onPointerUp() {
      const target = last.current;
      if (active.current === id && target) {
        const own = source.kind === "cell" ? sameCell(source, target) : false;
        if (!own) {
          dragged.current = true;
          onDrop(source, target);
        }
      }
      finish();
    },
    onPointerCancel: finish,
  });

  const wasDrag = () => {
    const was = dragged.current;
    dragged.current = false;
    return was;
  };

  return { dragging, over, handlers, wasDrag };
}
