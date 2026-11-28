import { useRef, useState } from "react";
import {
  applyCorrections,
  type Corrected,
  sameValue,
} from "../corrections/apply";
import { entryLabel } from "../corrections/rows";
import { saveEntryCorrection, useCorrector } from "../corrections/useCorrect";
import type { Correction, HistoryHow } from "../data/corrections";
import { maxCorrectedFields } from "../data/corrections";
import type { EventEntry } from "../data/parse";
import type { ScoutField } from "../scout/config";
import { type Edit, popEdit, pushEdit } from "./undoStack";

export interface CellEditor {
  commit(id: string, field: ScoutField, value: unknown): Promise<void>;
  undo(): Promise<void>;
  tell(message: string): void;
  setEditing(editing: boolean): void;
}

export interface EditorState {
  editor: CellEditor;
  editing: boolean;
  last: { entryId: string; what: string } | null;
  message: string;
}

export function useCellEditor(
  eventKey: string,
  fields: ScoutField[],
  getEntry: (id: string) => Corrected<EventEntry> | undefined,
): EditorState {
  const { author } = useCorrector(eventKey);
  const [stack, setStack] = useState<Edit[]>([]);
  const [editing, setEditing] = useState(false);
  const [last, setLast] = useState<EditorState["last"]>(null);
  const [message, setMessage] = useState("");
  const written = useRef(new Map<string, Correction>());
  const queue = useRef<Promise<void>>(Promise.resolve());

  const run = (task: () => Promise<void>) => {
    queue.current = queue.current.then(task, task);
    return queue.current;
  };

  const current = (id: string): Corrected<EventEntry> | undefined => {
    const entry = getEntry(id);
    const mine = written.current.get(id);
    if (!entry || !mine) return entry;
    const live = entry.correction;
    if (live && live.updatedMs > mine.updatedMs) return entry;
    return applyCorrections(
      [{ ...entry, fieldValues: entry.rawValues }],
      [mine],
    )[0];
  };

  async function write(
    entry: Corrected<EventEntry>,
    field: ScoutField,
    value: unknown,
    how: HistoryHow,
  ): Promise<boolean> {
    const next = { ...(entry.correction?.fields ?? {}) };
    if (sameValue(entry.rawValues[field.code], value)) delete next[field.code];
    else next[field.code] = value;
    if (Object.keys(next).length > maxCorrectedFields) {
      setMessage(
        `A correction holds up to ${maxCorrectedFields} changed answers.`,
      );
      return false;
    }
    try {
      const saved = await saveEntryCorrection(
        entry,
        entry.teamNumber,
        eventKey,
        author,
        next as Record<string, unknown>,
        entry.correction?.note ?? "",
        how,
      );
      written.current.set(entry.id, saved);
    } catch {
      setMessage("Could not save on this device. Try again.");
      return false;
    }
    setMessage("");
    setLast({
      entryId: entry.id,
      what: `${field.title.trim() || field.code}, team ${entry.teamNumber}, ${entryLabel(entry)}`,
    });
    return true;
  }

  const editor: CellEditor = {
    commit: (id, field, value) =>
      run(async () => {
        const entry = current(id);
        if (!entry || sameValue(entry.fieldValues[field.code], value)) return;
        const before = entry.fieldValues[field.code];
        if (await write(entry, field, value, "table")) {
          setStack((s) =>
            pushEdit(s, {
              entryId: id,
              field: field.code,
              before,
              after: value,
            }),
          );
        }
      }),
    undo: () =>
      run(async () => {
        const [edit, rest] = popEdit(stack);
        if (!edit) {
          setMessage("Nothing to undo.");
          return;
        }
        setStack(rest);
        const entry = current(edit.entryId);
        const field = fields.find((f) => f.code === edit.field);
        if (!entry || !field) return;
        if (!sameValue(entry.fieldValues[edit.field], edit.after)) {
          setMessage("Not undone: that answer was changed since.");
          return;
        }
        await write(entry, field, edit.before ?? "", "undo");
      }),
    tell: setMessage,
    setEditing,
  };
  return { editor, editing, last, message };
}
