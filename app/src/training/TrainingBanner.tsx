import { useLayoutEffect, useRef } from "react";
import {
  leaveTraining,
  type TrainingSession,
  useTrainingSession,
} from "./session";
import "./training.css";

function Bar({ session }: { session: TrainingSession }) {
  const ref = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const root = document.documentElement.style;
    const apply = () =>
      root.setProperty("--training-h", `${el.offsetHeight}px`);
    apply();
    const observer =
      typeof ResizeObserver === "undefined" ? null : new ResizeObserver(apply);
    observer?.observe(el);
    return () => {
      observer?.disconnect();
      root.removeProperty("--training-h");
    };
  }, []);

  return (
    <div className="training-banner" role="status" ref={ref}>
      <div className="training-text">
        <p>
          <strong>Training:</strong> past event {session.eventKey}, nothing is
          saved to the team database
        </p>
        <p className="secondary">
          {session.revealed} of {session.replay.matches.length} matches played
        </p>
      </div>
      <button type="button" className="btn" onClick={leaveTraining}>
        Leave training
      </button>
    </div>
  );
}

export function TrainingBanner() {
  const session = useTrainingSession();
  return session ? <Bar session={session} /> : null;
}
