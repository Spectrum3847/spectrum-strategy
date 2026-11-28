import { type PointerEvent, useRef, useState } from "react";

export type Drop =
  | { kind: "tier"; tier: number; index: number }
  | { kind: "pool" };

export function insertIndex(middles: number[], y: number): number {
  const at = middles.findIndex((m) => m > y);
  return at < 0 ? middles.length : at;
}

function dropAt(x: number, y: number, dragged: number): Drop | null {
  const zone = document
    .elementFromPoint(x, y)
    ?.closest<HTMLElement>("[data-drop]");
  if (!zone) return null;
  const id = zone.dataset.drop ?? "";
  if (id === "pool") return { kind: "pool" };
  const tier = Number(id.replace("tier-", ""));
  if (!Number.isInteger(tier)) return null;
  const rows = [
    ...zone.querySelectorAll<HTMLElement>("[data-row-team]"),
  ].filter((row) => Number(row.dataset.rowTeam) !== dragged);
  const middles = rows.map((row) => {
    const box = row.getBoundingClientRect();
    return box.top + box.height / 2;
  });
  return { kind: "tier", tier, index: insertIndex(middles, y) };
}

const edge = 64;

export type RowDrag = ReturnType<typeof useRowDrag>;

export function useRowDrag(onDrop: (team: number, drop: Drop) => void) {
  const [dragging, setDragging] = useState<number | null>(null);
  const [over, setOver] = useState<Drop | null>(null);
  const last = useRef<Drop | null>(null);

  const finish = () => {
    setDragging(null);
    setOver(null);
    last.current = null;
  };

  const handlers = (team: number) => ({
    onPointerDown(e: PointerEvent<HTMLElement>) {
      if (e.button !== 0) return;
      e.currentTarget.setPointerCapture(e.pointerId);
      setDragging(team);
    },
    onPointerMove(e: PointerEvent<HTMLElement>) {
      if (dragging !== team) return;
      if (e.clientY < edge) window.scrollBy(0, -12);
      else if (e.clientY > window.innerHeight - edge) window.scrollBy(0, 12);
      const next = dropAt(e.clientX, e.clientY, team);
      last.current = next;
      setOver(next);
    },
    onPointerUp() {
      if (dragging === team && last.current) onDrop(team, last.current);
      finish();
    },
    onPointerCancel: finish,
  });

  return { dragging, over, handlers };
}
