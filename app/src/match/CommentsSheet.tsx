import { type KeyboardEvent, type MouseEvent, useEffect, useRef } from "react";
import type { TeamComment } from "../team/format";
import { NoteList } from "../team/Sections";
import "../team/team.css";

const focusable = "a[href], button:not([disabled])";

export function CommentsSheet({
  title,
  notes,
  onClose,
}: {
  title: string;
  notes: TeamComment[];
  onClose(): void;
}) {
  const sheet = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    sheet.current?.querySelector<HTMLElement>(".sheet-close")?.focus();
    return () => opener?.focus();
  }, []);

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") {
      e.stopPropagation();
      onClose();
      return;
    }
    if (e.key !== "Tab") return;
    const items = [
      ...(sheet.current?.querySelectorAll<HTMLElement>(focusable) ?? []),
    ];
    const first = items[0];
    const last = items[items.length - 1];
    if (!first || !last) return;
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  const onClick = (e: MouseEvent<HTMLDivElement>) => {
    if ((e.target as HTMLElement).closest("a")) onClose();
  };

  return (
    <div className="sheet-scrim">
      <button
        type="button"
        className="sheet-backdrop"
        tabIndex={-1}
        aria-hidden="true"
        onClick={onClose}
      />
      <div
        ref={sheet}
        className="sheet comments-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="comments-sheet-title"
        onKeyDown={onKeyDown}
        onClick={onClick}
      >
        <div className="sheet-head">
          <h2 id="comments-sheet-title">{title}</h2>
          <button
            type="button"
            className="sheet-close"
            aria-label="Close"
            onClick={onClose}
          >
            <svg
              viewBox="0 0 24 24"
              width="24"
              height="24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              aria-hidden="true"
              focusable="false"
            >
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        </div>
        {notes.length === 0 ? (
          <p className="secondary">No written comments or notes yet.</p>
        ) : (
          <>
            <p className="secondary">{`${notes.length} in all, newest first.`}</p>
            <NoteList notes={notes} />
          </>
        )}
      </div>
    </div>
  );
}
