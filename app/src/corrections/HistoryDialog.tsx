import { useEffect, useRef } from "react";
import type { HistoryEntry } from "../data/corrections";
import type { ScoutField } from "../scout/config";
import { displayValue } from "../team/format";
import { when } from "../team/Sections";
import "./corrections.css";

const howText = { table: "Table", form: "Form", undo: "Undo" } as const;

const shown = (field: ScoutField | undefined, v: HistoryEntry["to"]) => {
  const text = field ? displayValue(field, v) : String(v);
  return text === "" ? "Blank" : text;
};

export function HistoryDialog({
  title,
  changes,
  fields,
  onClose,
}: {
  title: string;
  changes: HistoryEntry[];
  fields: ScoutField[];
  onClose(): void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (typeof dialog.showModal === "function") dialog.showModal();
    else dialog.setAttribute("open", "");
  }, []);
  const byCode = new Map(fields.map((f) => [f.code, f]));
  return (
    <dialog
      ref={ref}
      className="history-dialog"
      aria-label={title}
      onClose={onClose}
    >
      <h2>{title}</h2>
      {changes.length === 0 ? (
        <p className="secondary">No changes. This is what the scout entered.</p>
      ) : (
        <ol className="history-list">
          {changes.map((h, i) => {
            const field = byCode.get(h.field);
            return (
              // biome-ignore lint/suspicious/noArrayIndexKey: append-only list
              <li key={i} className="history-item">
                <strong>{field?.title.trim() || h.field}</strong>
                <span>
                  {`${shown(field, h.from)} to ${shown(field, h.to)}`}
                </span>
                <span className="secondary">
                  {[
                    h.by !== "" ? `by ${h.by}` : "",
                    howText[h.how],
                    h.at > 0 ? when(new Date(h.at).toISOString()) : "",
                  ]
                    .filter((p) => p !== "")
                    .join(", ")}
                </span>
              </li>
            );
          })}
        </ol>
      )}
      <button
        type="button"
        className="btn"
        onClick={() => {
          const dialog = ref.current;
          if (dialog && typeof dialog.close === "function") dialog.close();
          else onClose();
        }}
      >
        Close
      </button>
    </dialog>
  );
}
