import { type KeyboardEvent, useEffect, useRef, useState } from "react";
import type { PitEntry } from "../data/parse";
import { PhotoGallery } from "../photos/PhotoGallery";
import { answersFor } from "../team/format";
import "./aids.css";
import type { ScoutConfig } from "./config";

export function newestPit(
  entries: readonly PitEntry[],
  team: number,
): PitEntry | null {
  let best: PitEntry | null = null;
  for (const e of entries) {
    if (e.teamNumber === team && (!best || e.updatedAt > best.updatedAt)) {
      best = e;
    }
  }
  return best;
}

const focusable = "a[href], button:not([disabled])";

export function PitBar({
  team,
  entries,
  config,
}: {
  team: number;
  entries: readonly PitEntry[];
  config: ScoutConfig;
}) {
  const [open, setOpen] = useState(false);
  const entry = team > 0 ? newestPit(entries, team) : null;
  useEffect(() => {
    if (!entry) setOpen(false);
  }, [entry]);
  if (!entry) return null;
  return (
    <>
      <button
        type="button"
        className="pit-bar"
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        <span>Pit report, Team {team}</span>
        <span aria-hidden="true">Open</span>
      </button>
      {open && (
        <PitSheet
          team={team}
          entry={entry}
          config={config}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

function PitSheet({
  team,
  entry,
  config,
  onClose,
}: {
  team: number;
  entry: PitEntry;
  config: ScoutConfig;
  onClose(): void;
}) {
  const sheet = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    sheet.current?.querySelector<HTMLElement>("button")?.focus();
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
  const answers = answersFor(config, entry.fieldValues);
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
        className="sheet"
        role="dialog"
        aria-modal="true"
        aria-label={`Pit report, team ${team}`}
        onKeyDown={onKeyDown}
      >
        <div className="sheet-head">
          <h2>Pit report, Team {team}</h2>
          <button
            type="button"
            className="btn"
            aria-label="Close pit report"
            onClick={onClose}
          >
            Close
          </button>
        </div>
        {entry.scoutName && (
          <p className="secondary">Scouted by {entry.scoutName}</p>
        )}
        {answers.length === 0 ? (
          <p className="secondary">This pit record has no answers.</p>
        ) : (
          <dl className="pit-answers">
            {answers.map((a) => (
              <div key={a.label} className="pit-answer">
                <dt>{a.label}</dt>
                <dd>{a.value}</dd>
              </div>
            ))}
          </dl>
        )}
        <PhotoGallery keys={entry.photoKeys} />
      </div>
    </div>
  );
}
