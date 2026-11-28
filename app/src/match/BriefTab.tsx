import { useState } from "react";
import { Link } from "react-router";
import type { ScoutConfig } from "../scout/config";
import type { Delivery } from "../scout/ScoutForm";
import { DeliveryLine } from "../scout/ScoutForm";
import type { TeamComment } from "../team/format";
import type { TraitRating } from "../trex/ratings";
import type { Brief, Edit, RobotRoles } from "./brief";
import { CoachBrief } from "./CoachBrief";
import type { Forecast } from "./outside";
import {
  type Choice,
  type OverrideKind,
  optionsFor,
  type Plan,
  type Resolved,
  resolve,
  withOverride,
} from "./recommend";
import type { RobotRow, Side } from "./robots";

function Star() {
  return (
    <svg
      className="brief-star"
      viewBox="0 0 24 24"
      width="14"
      height="14"
      fill="currentColor"
      aria-hidden="true"
      focusable="false"
    >
      <path d="M12 2l3 6.9 7.5.7-5.7 5 1.7 7.4L12 18.2 5.5 22l1.7-7.4-5.7-5 7.5-.7z" />
    </svg>
  );
}

function Why({ done }: { done: Resolved }) {
  return (
    <p className="secondary brief-why" data-changed={done.changed}>
      {done.changed
        ? `Changed by you, recommended: ${done.recommended.value} (${done.recommended.why})`
        : done.recommended.why}
    </p>
  );
}

function Pickers({
  team,
  config,
  roles,
  plan,
  disabled,
  onChoose,
}: {
  team: number;
  config: ScoutConfig;
  roles: RobotRoles;
  plan: Plan;
  disabled: boolean;
  onChoose(kind: OverrideKind, value: string, done: Resolved): void;
}) {
  const job = resolve(config, "job", plan.job, roles);
  const select = (
    kind: "start" | "climb",
    label: string,
    choice: Choice | null,
  ) => {
    if (!choice) return null;
    const done = resolve(config, kind, choice, roles);
    return (
      <div className="match-field">
        <label className="field-name" htmlFor={`brief-${kind}-${team}`}>
          {label}
        </label>
        <select
          id={`brief-${kind}-${team}`}
          className="input"
          value={done.value}
          disabled={disabled}
          onChange={(e) => onChoose(kind, e.target.value, done)}
        >
          {optionsFor(config, kind).map((o) => (
            <option key={o} value={o}>
              {o === choice.value ? `${o} (recommended)` : o}
            </option>
          ))}
        </select>
        <Why done={done} />
      </div>
    );
  };
  return (
    <div className="brief-picks">
      <fieldset className="match-field brief-job">
        <legend className="field-name">Job this match</legend>
        <div className="chips brief-jobs">
          {optionsFor(config, "job").map((o) => (
            <button
              key={o}
              type="button"
              className="chip"
              aria-pressed={job.value === o}
              aria-label={o === plan.job.value ? `${o} (recommended)` : o}
              disabled={disabled}
              onClick={() => onChoose("job", o, job)}
            >
              {o}
              {o === plan.job.value && <Star />}
            </button>
          ))}
        </div>
        <Why done={job} />
      </fieldset>
      {select("start", "Start spot", plan.start)}
      {select("climb", "Climb this match", plan.climb)}
    </div>
  );
}

function Editor({
  rows,
  brief,
  config,
  plans,
  loaded,
  canSave,
  delivery,
  signedIn,
  onSave,
}: {
  rows: RobotRow[];
  brief: Brief;
  config: ScoutConfig;
  plans: Map<number, Plan>;
  loaded: boolean;
  canSave: boolean;
  delivery: Delivery | undefined;
  signedIn: boolean;
  onSave(edit: Edit): Promise<void>;
}) {
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const run = async (edit: Edit) => {
    setBusy(true);
    setFailed(false);
    try {
      await onSave(edit);
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  };

  const choose = (
    team: number,
    kind: OverrideKind,
    value: string,
    done: Resolved,
  ) => {
    if (value === done.value) return;
    const roles = brief.robotRoles[team] ?? {};
    const next = withOverride(
      config,
      roles,
      kind,
      value === done.recommended.value ? null : value,
    );
    void run({ robotRoles: { ...brief.robotRoles, [team]: next } });
  };

  return (
    <section className="match-section" aria-labelledby="brief-edit-h">
      <div className="match-section-head">
        <h2 id="brief-edit-h">Brief status</h2>
        <span className="coach-ready" data-ready={brief.ready}>
          {brief.ready ? "Ready" : "Draft"}
        </span>
      </div>
      <div className="actions">
        <button
          type="button"
          className={brief.ready ? "btn" : "btn primary"}
          disabled={busy || !canSave}
          onClick={() => void run({ ready: !brief.ready })}
        >
          {brief.ready ? "Mark as draft" : "Mark ready"}
        </button>
        {(delivery || failed) && (
          <span className="match-delivery" role="status">
            {failed ? (
              <span className="state" data-state="refused">
                Could not save on this device. Try again.
              </span>
            ) : (
              <DeliveryLine delivery={delivery} signedIn={signedIn} />
            )}
          </span>
        )}
      </div>

      <h2 id="plans-h">Job, start and climb</h2>
      <p className="secondary">
        Each choice is recommended from scouting data and already selected. Pick
        another only where you disagree. For opponents it is what we expect them
        to do.
      </p>
      <div className="match-plans">
        {rows.map((r) => {
          const plan = plans.get(r.team);
          return (
            <fieldset className="match-plan" key={r.team} data-side={r.side}>
              <legend>
                {r.team}
                {r.nickname !== "" && ` ${r.nickname}`}
              </legend>
              {plan && (
                <Pickers
                  team={r.team}
                  config={config}
                  roles={brief.robotRoles[r.team] ?? {}}
                  plan={plan}
                  disabled={!canSave || !loaded}
                  onChoose={(kind, value, done) =>
                    choose(r.team, kind, value, done)
                  }
                />
              )}
            </fieldset>
          );
        })}
      </div>
      {!canSave && <p className="secondary">Sign in to save the brief.</p>}
      {canSave && !loaded && (
        <p className="secondary" role="status">
          Loading scout entries. The choices open once the recommendations use
          all of them.
        </p>
      )}
    </section>
  );
}

export function BriefTab({
  rows,
  brief,
  config,
  plans,
  loaded,
  notes,
  ours,
  forecast,
  ratings,
  canEdit,
  canSave,
  delivery,
  signedIn,
  onSave,
}: {
  rows: RobotRow[];
  brief: Brief;
  config: ScoutConfig;
  plans: Map<number, Plan>;
  loaded: boolean;
  notes: Map<number, TeamComment[]>;
  ours: Side | null;
  forecast: Forecast | null;
  ratings: Map<number, TraitRating[]>;
  canEdit: boolean;
  canSave: boolean;
  delivery: Delivery | undefined;
  signedIn: boolean;
  onSave(edit: Edit): Promise<void>;
}) {
  if (ours === null) {
    return (
      <div className="now-empty">
        <p>
          Briefs cover the matches our team plays. Set your team number in
          Settings if this one should be ours.
        </p>
        <div className="actions">
          <Link className="btn" to="/settings?s=device">
            Open Settings
          </Link>
        </div>
      </div>
    );
  }
  return (
    <>
      {canEdit && (
        <Editor
          key={brief.id}
          rows={rows}
          brief={brief}
          config={config}
          plans={plans}
          loaded={loaded}
          canSave={canSave}
          delivery={delivery}
          signedIn={signedIn}
          onSave={onSave}
        />
      )}
      <CoachBrief
        rows={rows}
        brief={brief}
        config={config}
        plans={plans}
        notes={notes}
        ours={ours}
        forecast={forecast}
        ratings={ratings}
      />
    </>
  );
}
