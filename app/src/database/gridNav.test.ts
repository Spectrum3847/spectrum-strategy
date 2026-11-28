import { describe, expect, it } from "vitest";
import { move, tab } from "./gridNav";
import { heldRows, holdIds } from "./hold";
import type { DbRow } from "./rows";
import { popEdit, pushEdit, undoLimit } from "./undoStack";

const dims = { rows: 3, cols: 4 };

describe("move", () => {
  it("moves one cell and stops at the edges", () => {
    expect(move({ row: 1, col: 1 }, "down", dims)).toEqual({ row: 2, col: 1 });
    expect(move({ row: 2, col: 1 }, "down", dims)).toEqual({ row: 2, col: 1 });
    expect(move({ row: 0, col: 0 }, "up", dims)).toEqual({ row: 0, col: 0 });
    expect(move({ row: 0, col: 0 }, "left", dims)).toEqual({ row: 0, col: 0 });
    expect(move({ row: 0, col: 3 }, "right", dims)).toEqual({ row: 0, col: 3 });
  });

  it("jumps to the row's first and last cell", () => {
    expect(move({ row: 1, col: 2 }, "home", dims)).toEqual({ row: 1, col: 0 });
    expect(move({ row: 1, col: 2 }, "end", dims)).toEqual({ row: 1, col: 3 });
  });
});

describe("tab", () => {
  it("goes right, then wraps to the next row", () => {
    expect(tab({ row: 0, col: 1 }, false, dims)).toEqual({ row: 0, col: 2 });
    expect(tab({ row: 0, col: 3 }, false, dims)).toEqual({ row: 1, col: 0 });
  });

  it("goes left with Shift, wrapping to the row above", () => {
    expect(tab({ row: 1, col: 0 }, true, dims)).toEqual({ row: 0, col: 3 });
  });

  it("stops at the first and last cell", () => {
    expect(tab({ row: 2, col: 3 }, false, dims)).toEqual({ row: 2, col: 3 });
    expect(tab({ row: 0, col: 0 }, true, dims)).toEqual({ row: 0, col: 0 });
  });
});

describe("undo stack", () => {
  const edit = (n: number) => ({
    entryId: "a",
    field: "f",
    before: n,
    after: n + 1,
  });

  it("pops the newest edit first", () => {
    const stack = pushEdit(pushEdit([], edit(1)), edit(2));
    const [first, rest] = popEdit(stack);
    expect(first).toEqual(edit(2));
    expect(popEdit(rest)[0]).toEqual(edit(1));
  });

  it("returns nothing from an empty stack", () => {
    expect(popEdit([])).toEqual([null, []]);
  });

  it("keeps the newest edits only", () => {
    let stack: ReturnType<typeof pushEdit> = [];
    for (let i = 0; i < undoLimit + 5; i++) stack = pushEdit(stack, edit(i));
    expect(stack).toHaveLength(undoLimit);
    expect(stack[0]).toEqual(edit(5));
  });
});

describe("held rows", () => {
  const row = (id: string) => ({ id }) as DbRow;

  it("shows everything when nothing is held", () => {
    const rows = [row("a"), row("b")];
    expect(heldRows(rows, null)).toEqual({ shown: rows, waiting: 0 });
  });

  it("counts new entries without showing them, and drops removed ones", () => {
    const held = holdIds([row("a"), row("b")]);
    const out = heldRows([row("a"), row("c"), row("d")], held);
    expect(out.shown.map((r) => r.id)).toEqual(["a"]);
    expect(out.waiting).toBe(2);
  });
});
