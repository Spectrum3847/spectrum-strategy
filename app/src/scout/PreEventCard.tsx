import { Link } from "react-router";
import "./aids.css";

export function PreEventCard() {
  return (
    <section className="pre-event" aria-labelledby="pre-event-h">
      <h2 id="pre-event-h">Before the event: pre-scout</h2>
      <p>Watch a team's earlier matches and record what you see.</p>
      <Link className="btn primary" to="/scout/prescout">
        Pre-scout a team
      </Link>
    </section>
  );
}

export function showPreEvent(
  eventKey: string,
  schedule: ReadonlyArray<{ redScore?: number; blueScore?: number }>,
  entryCount: number,
): boolean {
  if (eventKey === "" || entryCount > 0) return false;
  return !schedule.some(
    (m) => (m.redScore ?? -1) >= 0 || (m.blueScore ?? -1) >= 0,
  );
}
