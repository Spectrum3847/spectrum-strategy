import { useEffect, useRef } from "react";
import { prescoutMatchLabel, watchedMatchId } from "../forms/entries";
import type { Values } from "../scout/config";
import type { PrescoutMatch } from "./finder";
import type { PlanState } from "./usePrescoutPlan";

const text = (values: Values, code: string) =>
  String(values[code] ?? "").trim();

export function fillFor(match: PrescoutMatch): Values {
  return {
    watchedEvent: match.eventName,
    matchType: match.matchType,
    matchNumber: match.number,
    videoUrl: match.videoUrl,
  };
}

const labelOf = (m: PrescoutMatch) => prescoutMatchLabel(m.matchType, m.number);
const idOf = (m: PrescoutMatch) => watchedMatchId(m.eventName, labelOf(m));

export function MatchPicker(props: {
  state: PlanState;
  values: Values;
  recorded: Set<string>;
  autopick: boolean;
  onPick(fill: Values): void;
}) {
  const { state, values, recorded, onPick } = props;
  const plan = state.plan;
  const picked = useRef(false);

  // biome-ignore lint/correctness/useExhaustiveDependencies: runs once per plan
  useEffect(() => {
    if (!props.autopick || picked.current || !plan) return;
    picked.current = true;
    const typed = ["watchedEvent", "matchNumber", "videoUrl"].some(
      (c) => text(values, c) !== "",
    );
    if (typed) return;
    const first = plan.matches.find((m) => !recorded.has(idOf(m)));
    if (first) onPick(fillFor(first));
  }, [plan]);

  const current = watchedMatchId(
    text(values, "watchedEvent"),
    prescoutMatchLabel(text(values, "matchType"), text(values, "matchNumber")),
  );
  const events = plan ? [...new Set(plan.matches.map((m) => m.eventName))] : [];

  return (
    <section className="match-picker panel" aria-labelledby="match-picker-h">
      <h2 id="match-picker-h" className="form-section">
        Matches with video
      </h2>
      {state.status === "loading" && !plan && (
        <p className="secondary" role="status">
          Finding matches with video.
        </p>
      )}
      {state.status === "failed" && (
        <p className="secondary" role="status">
          Could not reach The Blue Alliance and nothing is saved on this device.
          Type the match below, or paste a video link.
        </p>
      )}
      {plan && (
        <>
          {events.length > 0 && (
            <p className="secondary">{events.join(", ")}</p>
          )}
          {plan.note && <p className="secondary">{plan.note}</p>}
          {state.saved && (
            <p className="secondary" role="status">
              Offline or unreachable. Showing the list saved on this device.
            </p>
          )}
          {plan.matches.length > 0 && (
            <ul className="chips plain">
              {plan.matches.map((m) => {
                const done = recorded.has(idOf(m));
                const label = labelOf(m);
                return (
                  <li key={m.matchKey}>
                    <button
                      type="button"
                      className="chip"
                      disabled={done}
                      aria-pressed={!done && idOf(m) === current}
                      onClick={() => onPick(fillFor(m))}
                    >
                      {events.length > 1 ? `${label} - ${m.eventName}` : label}
                      {done ? " (saved)" : ""}
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </>
      )}
    </section>
  );
}
