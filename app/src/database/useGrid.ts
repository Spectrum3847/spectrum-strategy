import { type KeyboardEvent, useEffect, useRef, useState } from "react";
import { type ScoutField, selectedKeys } from "../scout/config";
import {
  blankCell,
  cellKind,
  editText,
  isOn,
  isReadOnly,
  parseCell,
} from "./cellValue";
import { arrowMoves, move, type Pos, tab } from "./gridNav";
import type { DbRow } from "./rows";
import type { CellEditor } from "./useCellEditor";

export interface Open {
  id: string;
  code: string;
  draft: string;
  picks: string[];
  error: string;
}

type Finish = "enter" | "tab" | "back" | "stay" | "cancel";

const typed = new Set(["text", "longText", "number", "counter", "range"]);

export function useGrid(
  rows: DbRow[],
  fields: ScoutField[],
  editor: CellEditor | undefined,
  onEngage?: () => void,
) {
  const [active, setActive] = useState<{ id: string; code: string } | null>(
    null,
  );
  const [open, setOpenState] = useState<Open | null>(null);
  const openRef = useRef<Open | null>(null);
  const refocus = useRef(false);
  const table = useRef<HTMLTableElement>(null);

  const rowAt = active ? rows.findIndex((r) => r.id === active.id) : -1;
  const colAt = active ? fields.findIndex((f) => f.code === active.code) : -1;
  const placed = rowAt >= 0 && colAt >= 0;
  const dims = { rows: rows.length, cols: fields.length };
  const posOf = (id: string, code: string): Pos => ({
    row: rows.findIndex((r) => r.id === id),
    col: fields.findIndex((f) => f.code === code),
  });

  useEffect(() => {
    if (!refocus.current || open) return;
    refocus.current = false;
    table.current
      ?.querySelector<HTMLElement>('[data-cell][tabindex="0"]')
      ?.focus();
  });

  const setOpen = (next: Open | null) => {
    openRef.current = next;
    setOpenState(next);
    editor?.setEditing(next !== null);
  };

  const update = (patch: Partial<Open>) => {
    if (!openRef.current) return;
    const next = { ...openRef.current, error: "", ...patch };
    openRef.current = next;
    setOpenState(next);
  };

  const focusAt = (p: Pos) => {
    const row = rows[p.row];
    const field = fields[p.col];
    if (!row || !field) return;
    refocus.current = true;
    setActive({ id: row.id, code: field.code });
  };

  const flip = (row: DbRow, field: ScoutField) =>
    void editor?.commit(row.id, field, !isOn(row.values[field.code]));

  const begin = (row: DbRow, field: ScoutField, seed?: string) => {
    if (!editor || isReadOnly(field)) return;
    const kind = cellKind(field);
    if (kind === "boolean") return flip(row, field);
    const value = row.values[field.code];
    setActive({ id: row.id, code: field.code });
    setOpen({
      id: row.id,
      code: field.code,
      draft: seed ?? editText(field, value),
      picks: kind === "multi" ? selectedKeys(value) : [],
      error: "",
    });
  };

  const finish = (how: Finish) => {
    const o = openRef.current;
    if (!o || !editor) return;
    const field = fields.find((f) => f.code === o.code);
    if (!field || how === "cancel") {
      setOpen(null);
      refocus.current = true;
      return;
    }
    const text = cellKind(field) === "multi" ? o.picks.join(",") : o.draft;
    const parsed = parseCell(field, text);
    if (!parsed.ok) {
      if (how === "stay") {
        setOpen(null);
        editor.tell(parsed.reason);
      } else {
        update({ error: parsed.reason });
      }
      return;
    }
    setOpen(null);
    void editor.commit(o.id, field, parsed.value);
    if (how === "stay") return;
    const here = posOf(o.id, o.code);
    focusAt(
      how === "enter"
        ? move(here, "down", dims)
        : tab(here, how === "back", dims),
    );
  };

  const keyEditing = (e: KeyboardEvent, field: ScoutField) => {
    if (e.key === "Enter") {
      if (cellKind(field) === "longText" && e.shiftKey) return;
      e.preventDefault();
      finish("enter");
    } else if (e.key === "Tab") {
      e.preventDefault();
      finish(e.shiftKey ? "back" : "tab");
    } else if (e.key === "Escape") {
      e.preventDefault();
      finish("cancel");
    }
  };

  const keyMoving = (e: KeyboardEvent, row: DbRow, field: ScoutField) => {
    if (!editor) return;
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
      e.preventDefault();
      void editor.undo();
      return;
    }
    const to = arrowMoves[e.key];
    if (to) {
      e.preventDefault();
      focusAt(move(posOf(row.id, field.code), to, dims));
      return;
    }
    if (isReadOnly(field)) return;
    const kind = cellKind(field);
    if (e.key === "Enter" || e.key === "F2") {
      e.preventDefault();
      begin(row, field);
    } else if (e.key === " " && kind === "boolean") {
      e.preventDefault();
      flip(row, field);
    } else if (e.key === "Delete" || e.key === "Backspace") {
      e.preventDefault();
      const blank = blankCell(field);
      if (blank.ok) void editor.commit(row.id, field, blank.value);
      else editor.tell(blank.reason);
    } else if (
      e.key.length === 1 &&
      !e.ctrlKey &&
      !e.metaKey &&
      !e.altKey &&
      typed.has(kind)
    ) {
      e.preventDefault();
      begin(row, field, e.key);
    }
  };

  const onKeyDown = (e: KeyboardEvent, row: DbRow, field: ScoutField) => {
    const o = openRef.current;
    if (!o) return keyMoving(e, row, field);
    if (o.id === row.id && o.code === field.code) keyEditing(e, field);
  };

  const onClick = (row: DbRow, field: ScoutField) => {
    const o = openRef.current;
    if (o && o.id === row.id && o.code === field.code) return;
    setActive({ id: row.id, code: field.code });
    begin(row, field);
  };

  const isStop = (r: number, c: number) =>
    placed ? r === rowAt && c === colAt : r === 0 && c === 0;

  return {
    table,
    open,
    update,
    finish,
    onKeyDown,
    onClick,
    onFocusCell: (row: DbRow, field: ScoutField) => {
      setActive({ id: row.id, code: field.code });
      onEngage?.();
    },
    isStop,
    enabled: editor !== undefined,
  };
}

export type Grid = ReturnType<typeof useGrid>;
