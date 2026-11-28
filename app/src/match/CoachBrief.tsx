import { useState } from "react";
import type { ScoutConfig } from "../scout/config";
import type { TeamComment } from "../team/format";
import { Lines } from "../team/Sections";
import { ratingText, type TraitRating } from "../trex/ratings";
import { TeamLink } from "../ui/TeamLink";
import type { Brief } from "./brief";
import { CommentsSheet } from "./CommentsSheet";
import type { Forecast } from "./outside";
import { type Plan, type Resolved, resolve } from "./recommend";
import { factsFor, type RobotRow, type Side } from "./robots";

const sideName: Record<Side, string> = { red: "Red", blue: "Blue" };

export function CoachBrief({
  rows,
  brief,
  config,
  plans,
  notes,
  ours,
  forecast,
  ratings,
}: {
  rows: RobotRow[];
  brief: Brief;
  config: ScoutConfig;
  plans: Map<number, Plan>;
  notes: Map<number, TeamComment[]>;
  ours: Side;
  forecast: Forecast | null;
  ratings: Map<number, TraitRating[]>;
}) {
  return (
    <div className="coach">
      <section className="coach-head" aria-labelledby="coach-h">
        <div className="coach-title">
          <h2 id="coach-h">Match brief</h2>
          <span className="coach-ready" data-ready={brief.ready}>
            {brief.ready ? "Ready" : "Draft"}
          </span>
        </div>
        <p>
          We are{" "}
          <span className="tag" data-alliance={ours}>
            {sideName[ours]}
          </span>
        </p>
        {forecast && <ForecastLine forecast={forecast} ours={ours} />}
        {!brief.ready && (
          <p className="coach-muted">
            Draft: the strategy lead has not marked this ready.
          </p>
        )}
        {brief.authorDisplayName !== "" && (
          <p className="secondary">Written by {brief.authorDisplayName}</p>
        )}
      </section>
      <div className="coach-panels">
        <Panel
          side="red"
          heading={ours === "red" ? "Our alliance" : "Opponents"}
          rows={rows}
          brief={brief}
          config={config}
          plans={plans}
          notes={notes}
          ratings={ratings}
          threat={ours !== "red"}
        />
        <Panel
          side="blue"
          heading={ours === "blue" ? "Our alliance" : "Opponents"}
          rows={rows}
          brief={brief}
          config={config}
          plans={plans}
          notes={notes}
          ratings={ratings}
          threat={ours !== "blue"}
        />
      </div>
    </div>
  );
}

function ForecastLine({ forecast, ours }: { forecast: Forecast; ours: Side }) {
  const mine = ours === "red" ? forecast.redScore : forecast.blueScore;
  const theirs = ours === "red" ? forecast.blueScore : forecast.redScore;
  const win = ours === "red" ? forecast.redWin : 1 - forecast.redWin;
  return (
    <p>
      The Blue Alliance forecast: we score {Math.round(mine)}, they score{" "}
      {Math.round(theirs)}, our win chance {Math.round(win * 100)}%
    </p>
  );
}

function Threat({ rows }: { rows: RobotRow[] }) {
  let top: RobotRow | null = null;
  for (const r of rows) {
    if (r.epa !== null && (top === null || r.epa > (top.epa ?? 0))) top = r;
  }
  if (top === null || top.epa === null) return null;
  return (
    <p>
      Highest EPA: {top.team} ({top.epa.toFixed(1)})
    </p>
  );
}

function Panel({
  side,
  heading,
  rows,
  brief,
  config,
  plans,
  notes,
  ratings,
  threat,
}: {
  side: Side;
  heading: string;
  rows: RobotRow[];
  brief: Brief;
  config: ScoutConfig;
  plans: Map<number, Plan>;
  notes: Map<number, TeamComment[]>;
  ratings: Map<number, TraitRating[]>;
  threat: boolean;
}) {
  const robots = rows.filter((r) => r.side === side);
  return (
    <section className="coach-panel" data-side={side}>
      <div className="coach-title">
        <h3>{heading}</h3>
        <span className="tag" data-alliance={side}>
          {sideName[side]}
        </span>
      </div>
      {threat && <Threat rows={robots} />}
      {robots.map((r) => (
        <Robot
          key={r.team}
          row={r}
          brief={brief}
          config={config}
          plan={plans.get(r.team) ?? null}
          notes={notes.get(r.team) ?? []}
          ratings={ratings.get(r.team) ?? []}
        />
      ))}
    </section>
  );
}

function Mark({ done }: { done: Resolved }) {
  return done.changed ? null : (
    <span className="coach-muted"> (recommended)</span>
  );
}

function Robot({
  row,
  brief,
  config,
  plan,
  notes,
  ratings,
}: {
  row: RobotRow;
  brief: Brief;
  config: ScoutConfig;
  plan: Plan | null;
  notes: TeamComment[];
  ratings: TraitRating[];
}) {
  const [open, setOpen] = useState(false);
  const roles = brief.robotRoles[row.team] ?? {};
  const job = plan ? resolve(config, "job", plan.job, roles) : null;
  const start = plan?.start
    ? resolve(config, "start", plan.start, roles)
    : null;
  const climb = plan?.climb
    ? resolve(config, "climb", plan.climb, roles)
    : null;
  const picks = [
    { label: "Job", done: job },
    { label: "Start", done: start },
    { label: "Climb", done: climb },
  ];
  const summary = row.summary;
  const reading = [
    ...(summary.trend ? [summary.trend.line] : []),
    ...summary.strengths,
    ...summary.concerns,
  ];
  return (
    <div className="coach-robot">
      <p className="coach-robot-name">
        <TeamLink team={row.team} />
        {row.nickname !== "" && <span>{row.nickname}</span>}
      </p>
      <ul className="coach-plan" aria-label="Plan">
        {picks.map(({ label, done }) =>
          done ? (
            <li key={label} className="coach-strong">
              {label}: {done.value}
              <Mark done={done} />
            </li>
          ) : null,
        )}
      </ul>
      {climb && (
        <p className="coach-strong coach-climb">
          Climb?{" "}
          {climb.changed
            ? `You chose ${climb.value}. Data says ${climb.recommended.value}: ${climb.recommended.why}`
            : climb.recommended.why}
        </p>
      )}
      <ul className="coach-facts">
        {factsFor(row).map((fact) => (
          <li key={fact}>{fact}</li>
        ))}
      </ul>
      {ratings.length > 0 && (
        <ul className="coach-facts" aria-label="T-REx ratings">
          {ratings.map((r) => (
            <li key={r.key}>
              {r.label}: {ratingText(r)}
            </li>
          ))}
        </ul>
      )}
      <div className="coach-scouts">
        <p className="coach-strong">What scouts said</p>
        {reading.length === 0 ? (
          <p className="coach-muted">Not enough scouted matches yet.</p>
        ) : (
          <Lines title="" lines={reading} />
        )}
        <button
          type="button"
          className="btn"
          disabled={notes.length === 0}
          onClick={() => setOpen(true)}
        >
          All scout comments ({notes.length})
        </button>
      </div>
      {open && (
        <CommentsSheet
          title={`${row.team}: all scout comments`}
          notes={notes}
          onClose={() => setOpen(false)}
        />
      )}
    </div>
  );
}
