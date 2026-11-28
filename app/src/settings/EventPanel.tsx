import { type FormEvent, useMemo, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { useRoles } from "../auth/rolesContext";
import { dismissItem, enqueueWrite } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { useScoutData } from "../scout/ScoutData";
import { DeliveryState } from "../shifts/MyShifts";
import { EventPicker } from "./EventPicker";
import {
  activeEventDoc,
  activeEventPath,
  canSetTeamEvent,
  type SeasonEvent,
} from "./events";
import { savedEventName } from "./useSeasonEvents";

const scheduleText = {
  none: "No schedule",
  loading: "Loading the schedule",
  ready: "Schedule loaded",
  failed: "Schedule not available",
} as const;

export function EventPanel() {
  const data = useScoutData();
  const auth = useAuth();
  const roles = useRoles();
  const outbox = useOutbox();
  const [picking, setPicking] = useState(false);
  const [typed, setTyped] = useState("");
  const [saveError, setSaveError] = useState<string | null>(null);

  const signedIn = auth.status === "signed-in";
  const setsTeamEvent =
    signedIn && roles.status === "ready" && canSetTeamEvent(roles.roles);
  const teams = useMemo(
    () => new Set(data.schedule.flatMap((m) => [...m.red, ...m.blue])).size,
    [data.schedule],
  );
  const matches = data.schedule.filter((m) => m.compLevel === "qm").length;
  const name = data.eventKey === "" ? null : savedEventName(data.eventKey);
  const item = outbox.find((i) => i.path === activeEventPath);

  const choose = async (key: string) => {
    setPicking(false);
    setSaveError(null);
    if (key === data.eventKey) {
      void data.refreshSchedule();
      return;
    }
    data.setEventKey(key);
    if (!setsTeamEvent) return;
    try {
      await enqueueWrite(
        activeEventPath,
        activeEventDoc(key, new Date()),
        "Team event",
      );
    } catch (error) {
      const why =
        error instanceof Error ? error.message : "Could not save the event.";
      setSaveError(
        `This device now uses ${key}, but the team's event did not change. ${why}`,
      );
    }
  };

  const submitTyped = (e: FormEvent) => {
    e.preventDefault();
    const key = typed.trim();
    if (key === "") return;
    setTyped("");
    void choose(key);
  };

  return (
    <section className="panel" aria-labelledby="event-h">
      <h2 id="event-h">Event</h2>
      <p className="secondary">
        {setsTeamEvent
          ? "As a lead, the event you choose here becomes the event on every signed-in device."
          : "This device follows the team's event while you are signed in. Your pick here lasts until the team's event changes."}
      </p>
      <dl className="rows">
        <dt>Event</dt>
        <dd>{name ?? (data.eventKey || "None")}</dd>
        {name && (
          <>
            <dt>Key</dt>
            <dd>{data.eventKey}</dd>
          </>
        )}
        <dt>Teams</dt>
        <dd>{teams > 0 ? teams : "Not known yet"}</dd>
        <dt>Schedule</dt>
        <dd>
          {scheduleText[data.scheduleStatus]}
          {matches > 0 && `, ${matches} qualification matches`}
          {data.scheduleFetchedAt &&
            `, updated ${new Date(data.scheduleFetchedAt).toLocaleTimeString()}`}
        </dd>
        <dt>Match form</dt>
        <dd>Revision {data.config.revision}</dd>
      </dl>
      {picking ? (
        <EventPicker
          currentKey={data.eventKey}
          onPick={(event: SeasonEvent) => void choose(event.key)}
          onCancel={() => setPicking(false)}
        />
      ) : (
        <div className="actions">
          <button
            type="button"
            className="btn primary"
            onClick={() => setPicking(true)}
          >
            {data.eventKey === "" ? "Select event" : "Change event"}
          </button>
          <button
            type="button"
            className="btn"
            disabled={data.eventKey === ""}
            onClick={() => void data.refreshSchedule()}
          >
            Refresh schedule
          </button>
        </div>
      )}
      {saveError && (
        <p className="notice" role="alert">
          {saveError}
        </p>
      )}
      {setsTeamEvent && item && (
        <div aria-live="polite">
          <DeliveryState
            delivery={{
              id: item.id,
              status: item.status,
              ...(item.error ? { error: item.error } : {}),
            }}
            onDismiss={dismissItem}
          />
          {item.status === "refused" && (
            <p className="secondary">
              Only this device changed event. Other devices keep the team's
              event until a lead sets it again.
            </p>
          )}
        </div>
      )}
      <details className="event-key">
        <summary>Enter an event key</summary>
        <form className="actions" onSubmit={submitTyped}>
          <input
            className="input"
            aria-label="Event key"
            placeholder="2027test"
            value={typed}
            onChange={(e) => setTyped(e.target.value)}
          />
          <button type="submit" className="btn" disabled={typed.trim() === ""}>
            Use this event
          </button>
        </form>
      </details>
    </section>
  );
}
