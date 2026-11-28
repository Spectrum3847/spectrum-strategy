import { type KeyboardEvent, useEffect, useRef, useState } from "react";
import { refreshEventData } from "../data/refresh";
import { useSyncNotes } from "../data/syncState";
import { useTbaEvent } from "../data/useTbaEvent";
import { useEpa } from "../match/useOutside";
import { resendNow } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { useScoutData } from "../scout/ScoutData";
import { unsentCounts } from "../ui/unsent";
import { useOnline } from "../ui/useOnline";
import {
  type ApiInput,
  type Freshness,
  freshnessOf,
  longAgo,
  type Source,
} from "./freshness";
import "./freshness.css";

const focusable = "button:not([disabled])";

function useNow(everyMs = 30_000): number {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), everyMs);
    return () => clearInterval(timer);
  }, [everyMs]);
  return now;
}

function useFreshness(event?: ApiInput[]): Freshness {
  const counts = unsentCounts(useOutbox());
  const online = useOnline();
  const notes = useSyncNotes();
  const now = useNow();
  return freshnessOf({
    online,
    pending: counts.pending,
    refused: counts.refused,
    notes,
    ...(event ? { event } : {}),
    now,
  });
}

function Cloud({ level }: { level: Source["level"] }) {
  return (
    <svg
      className="fresh-icon"
      viewBox="0 0 24 24"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M7 18a4 4 0 0 1-.5-7.97A5.5 5.5 0 0 1 17 8.5 4.75 4.75 0 0 1 17 18z" />
      {level === "ok" && <path d="M9.5 13l2 2 3.5-3.5" />}
      {level === "attention" && <path d="M12 10v3M12 15.5v.01" />}
    </svg>
  );
}

function SourceRow({ source, now }: { source: Source; now: number }) {
  const stamp = source.live
    ? "Live now"
    : source.updatedMs === null
      ? "No update yet"
      : `Updated ${longAgo(source.updatedMs, now)}`;
  return (
    <li className="fresh-row" data-level={source.level}>
      <Cloud level={source.level} />
      <div className="fresh-text">
        <strong>{source.name}</strong>
        <span className="secondary">{source.status}</span>
      </div>
      <span className="secondary fresh-stamp">{stamp}</span>
    </li>
  );
}

function EventSheet({ onClose }: { onClose(): void }) {
  const { eventKey } = useScoutData();
  const tba = useTbaEvent();
  const epa = useEpa(eventKey);
  const online = useOnline();
  const now = useNow();
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState("");
  const sheet = useRef<HTMLDivElement>(null);
  const event: ApiInput[] =
    eventKey === ""
      ? []
      : [
          {
            name: "Event data (The Blue Alliance)",
            status: tba.status,
            fetchedAt: tba.fetchedAt,
          },
          {
            name: "Event data (Statbotics)",
            status: epa.status,
            fetchedAt: epa.fetchedAt ?? null,
          },
        ];
  const freshness = useFreshness(event);

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    sheet.current?.querySelector<HTMLElement>(focusable)?.focus();
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

  const syncNow = () => {
    resendNow();
    setNote(
      online
        ? "Sending what is waiting."
        : "No connection. What is waiting sends when this device is back online.",
    );
  };
  const refresh = async () => {
    setBusy(true);
    setNote("");
    try {
      await refreshEventData();
      setNote("Event data refreshed.");
    } finally {
      setBusy(false);
    }
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
        className="sheet fresh-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="fresh-title"
        onKeyDown={onKeyDown}
      >
        <div className="sheet-head">
          <h2 id="fresh-title">Is my data up to date?</h2>
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
        <p>{freshness.answer}</p>
        {freshness.unsent > 0 && (
          <p className="fresh-unsent">
            {freshness.unsent === 1
              ? "1 write is not in the database."
              : `${freshness.unsent} writes are not in the database.`}
          </p>
        )}
        <ul className="fresh-list">
          {freshness.sources.map((s) => (
            <SourceRow key={s.name} source={s} now={now} />
          ))}
          {eventKey === "" && (
            <li className="fresh-row" data-level="idle">
              <Cloud level="idle" />
              <div className="fresh-text">
                <strong>Event data</strong>
                <span className="secondary">No event selected</span>
              </div>
            </li>
          )}
        </ul>
        <div className="actions">
          <button type="button" className="btn primary" onClick={syncNow}>
            Sync now
          </button>
          <button
            type="button"
            className="btn"
            disabled={busy || eventKey === ""}
            onClick={() => void refresh()}
          >
            Refresh event data
          </button>
        </div>
        <p className="secondary" role="status">
          {note}
        </p>
      </div>
    </div>
  );
}

export function FreshnessPill() {
  const freshness = useFreshness();
  const [open, setOpen] = useState(false);
  const button = useRef<HTMLButtonElement>(null);
  const close = () => {
    setOpen(false);
    button.current?.focus();
  };
  return (
    <div className="fresh-bar">
      <button
        ref={button}
        type="button"
        className="fresh-pill"
        data-level={freshness.level}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label={`Data status: ${freshness.pillLabel}. Open details.`}
        onClick={() => setOpen(true)}
      >
        <Cloud level={freshness.level} />
        <span className="fresh-label" aria-hidden="true">
          {freshness.pillLabel}
        </span>
        {freshness.unsent > 0 && (
          <span className="fresh-count" aria-hidden="true">
            {freshness.unsent}
          </span>
        )}
      </button>
      {open && <EventSheet onClose={close} />}
    </div>
  );
}
