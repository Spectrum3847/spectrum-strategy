import { doc, onSnapshot } from "firebase/firestore";
import { useEffect, useState } from "react";
import { db } from "../firebase/client";
import "../scout/aids.css";
import {
  includes,
  parsePitSchedule,
  rangeText,
  type PitSchedule as Schedule,
} from "./pit";

export type State = {
  load: "loading" | "ready" | "failed";
  schedule: Schedule | null;
};

function usePitSchedule(eventKey: string, signedIn: boolean): State {
  const [state, setState] = useState<State>({
    load: "loading",
    schedule: null,
  });
  useEffect(() => {
    setState({ load: "loading", schedule: null });
    if (!signedIn || eventKey === "") return;
    return onSnapshot(
      doc(db, "pitShifts", eventKey),
      (snap) =>
        setState({
          load: "ready",
          schedule: snap.exists() ? parsePitSchedule(snap.data()) : null,
        }),
      () => setState((s) => ({ ...s, load: "failed" })),
    );
  }, [eventKey, signedIn]);
  return state;
}

const synced = (d: Date) =>
  d.toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

export function PitScheduleSection({
  eventKey,
  uid,
}: {
  eventKey: string;
  uid: string | null;
}) {
  const { load, schedule } = usePitSchedule(eventKey, uid !== null);
  return <PitScheduleView load={load} schedule={schedule} uid={uid} />;
}

export function PitScheduleView({
  load,
  schedule,
  uid,
}: State & { uid: string | null }) {
  if (load === "failed") {
    return (
      <section className="shift-section" aria-labelledby="pit-h">
        <h2 id="pit-h">Pit schedule</h2>
        <p className="secondary">The pit schedule could not be read.</p>
      </section>
    );
  }
  if (!schedule || schedule.shifts.length === 0) return null;
  const mine = uid ? schedule.shifts.filter((s) => includes(s, uid)).length : 0;
  const summary = [
    `${schedule.shifts.length} ${schedule.shifts.length === 1 ? "shift" : "shifts"}`,
    uid !== null && `${mine} yours`,
    schedule.syncedAt && `synced ${synced(schedule.syncedAt)}`,
  ]
    .filter(Boolean)
    .join(", ");
  return (
    <section className="shift-section" aria-labelledby="pit-h">
      <h2 id="pit-h">Pit schedule</h2>
      <p className="secondary">{summary}</p>
      <ul className="pit-shifts">
        {schedule.shifts.map((s, i) => {
          const range = rangeText(s);
          const names = s.assignees.map((a) => a.name).join(", ");
          return (
            <li
              // biome-ignore lint/suspicious/noArrayIndexKey: ids can repeat or be empty
              key={`${s.id}-${i}`}
              className="pit-shift"
              data-mine={uid !== null && includes(s, uid)}
            >
              <span>
                <span className="pit-shift-name">{s.label || s.kind}</span>
                <span className="secondary">{names || "Unassigned"}</span>
              </span>
              {range && <span>{range}</span>}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
