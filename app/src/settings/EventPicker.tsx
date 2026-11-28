import { useId, useMemo, useState } from "react";
import { filterEvents, type SeasonEvent, weekLabel } from "./events";
import { useSeasonEvents } from "./useSeasonEvents";

const firstSeason = 1992;

export function EventPicker({
  currentKey,
  onPick,
  onCancel,
}: {
  currentKey: string;
  onPick(event: SeasonEvent): void;
  onCancel(): void;
}) {
  const thisYear = new Date().getFullYear();
  const [year, setYear] = useState(thisYear);
  const [query, setQuery] = useState("");
  const [showAll, setShowAll] = useState(false);
  const { status, events } = useSeasonEvents(year);
  const searchId = useId();
  const shown = useMemo(
    () => filterEvents(events, { query, showAll, now: new Date() }),
    [events, query, showAll],
  );

  const toggleAll = (next: boolean) => {
    setShowAll(next);
    if (!next) setYear(thisYear);
  };

  return (
    <div className="event-picker">
      <label className="event-picker-all">
        <input
          type="checkbox"
          checked={showAll}
          onChange={(e) => toggleAll(e.target.checked)}
        />
        Show all events
      </label>
      {showAll && (
        <div className="event-picker-year">
          <button
            type="button"
            className="btn"
            aria-label="Previous season"
            disabled={year <= firstSeason}
            onClick={() => setYear(year - 1)}
          >
            Earlier
          </button>
          <strong>{year}</strong>
          <button
            type="button"
            className="btn"
            aria-label="Next season"
            disabled={year >= thisYear}
            onClick={() => setYear(year + 1)}
          >
            Later
          </button>
        </div>
      )}
      <label className="sr-only" htmlFor={searchId}>
        Search events by name or key
      </label>
      <input
        id={searchId}
        className="input"
        type="search"
        placeholder="Search by name or key"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
      />
      {status === "failed" && (
        <p className="notice" role="alert">
          {events.length > 0
            ? "Could not reach The Blue Alliance. This is the list saved on this device."
            : "Could not load the event list. Check the connection, or enter the event key below."}
        </p>
      )}
      <div className="event-picker-list" aria-live="polite">
        {status === "loading" && events.length === 0 ? (
          <p className="secondary">Loading the event list.</p>
        ) : shown.length === 0 && status !== "failed" ? (
          <p className="secondary">
            {showAll || query.trim() !== ""
              ? "No events found."
              : "No events nearby. Turn on Show all events to pick another."}
          </p>
        ) : (
          <ul className="plain">
            {shown.map((event) => (
              <li key={event.key}>
                <button
                  type="button"
                  className="event-picker-item"
                  aria-current={event.key === currentKey ? "true" : undefined}
                  onClick={() => onPick(event)}
                >
                  <span className="event-picker-name">{event.name}</span>
                  <span className="secondary">
                    {weekLabel(event)}, {event.key}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className="actions">
        <button type="button" className="btn" onClick={onCancel}>
          Cancel
        </button>
      </div>
    </div>
  );
}
