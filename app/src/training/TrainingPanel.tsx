import { useState } from "react";
import { useOnline } from "../ui/useOnline";
import { loadReplay, parseEventKey } from "./load";
import { nextLabel } from "./replay";
import {
  leaveTraining,
  playNextMatch,
  restartTraining,
  startTraining,
  useTrainingSession,
} from "./session";
import "./training.css";

function StartForm() {
  const online = useOnline();
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const key = parseEventKey(draft);

  async function start() {
    if (!key) return;
    setBusy(true);
    setError(null);
    try {
      startTraining(key, await loadReplay(key));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not load the event.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <p className="secondary">
        Replay a past event match by match. Scouts practice the match form and
        leads read Now, Schedule, Team and Match as they would at the event.
        Everything stays on this device and the team's event is not changed.
      </p>
      <form
        className="actions"
        onSubmit={(e) => {
          e.preventDefault();
          void start();
        }}
      >
        <input
          className="input"
          aria-label="Past event key"
          placeholder="2026cur"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button
          type="submit"
          className="btn primary"
          disabled={!key || busy || !online}
        >
          {busy ? "Loading the event" : "Start training"}
        </button>
      </form>
      {!online && (
        <p className="secondary">Go online to load the event's matches.</p>
      )}
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
    </>
  );
}

function Running() {
  const session = useTrainingSession();
  if (!session) return null;
  const total = session.replay.matches.length;
  const next = nextLabel(session.replay, session.revealed);
  return (
    <>
      <dl className="rows">
        <dt>Event</dt>
        <dd>{session.eventKey}</dd>
        <dt>Played</dt>
        <dd>
          {session.revealed} of {total} matches
        </dd>
        <dt>Next</dt>
        <dd>{next ?? "The replay is finished"}</dd>
      </dl>
      <div className="actions">
        <button
          type="button"
          className="btn primary"
          disabled={next === null}
          onClick={playNextMatch}
        >
          Play next match
        </button>
        <button type="button" className="btn" onClick={restartTraining}>
          Restart replay
        </button>
        <button type="button" className="btn" onClick={leaveTraining}>
          Leave training
        </button>
      </div>
      <p className="secondary">
        Leaving or restarting removes this device's training entries.
      </p>
    </>
  );
}

export function TrainingPanel() {
  const session = useTrainingSession();
  return (
    <section className="panel" aria-labelledby="training-h">
      <h2 id="training-h">Training</h2>
      {session ? <Running /> : <StartForm />}
    </section>
  );
}
