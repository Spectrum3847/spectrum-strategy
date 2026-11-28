import { type ReactNode, useState } from "react";
import { Link } from "react-router";
import { PredictionLine } from "../accuracy/PredictionLine";
import { canOpenMatchPage, isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { FilterChips } from "../forms/ListParts";
import { formatTime, matchLabel, timeLine } from "../now/matches";
import { useMyTeam } from "../now/myTeam";
import { useScoutData } from "../scout/ScoutData";
import type { ScheduledMatch } from "../scout/schedule";
import { TeamLink } from "../ui/TeamLink";
import { useOnline } from "../ui/useOnline";
import {
  ourOutcome,
  ourSide,
  resultText,
  type Side,
  splitSchedule,
  winnerOf,
} from "./rows";
import "./schedule.css";

type Scope = "all" | "ours";

function AllianceLine(props: {
  side: Side;
  teams: number[];
  us: number | null;
  score: number | undefined;
  won: boolean;
}) {
  const { side, teams, us, score, won } = props;
  return (
    <div className="sched-alliance">
      <span className="tag" data-alliance={side.toLowerCase()}>
        {side}
      </span>
      <ul className="plain sched-teams">
        {teams.map((team) => (
          <li key={team} data-us={team === us}>
            <TeamLink team={team} />
            {team === us && <span className="us">us</span>}
          </li>
        ))}
      </ul>
      {score !== undefined && (
        <span className="sched-score" data-won={won}>
          <span className="sr-only">{side} score </span>
          {score}
        </span>
      )}
    </div>
  );
}

function MatchRow(props: {
  match: ScheduledMatch;
  us: number | null;
  now: Date;
  linked: boolean;
}) {
  const { match, us, now, linked } = props;
  const label = matchLabel(match);
  const side = ourSide(match, us);
  const result = resultText(match);
  const winner = winnerOf(match);
  const outcome = ourOutcome(match, us);
  const time = result ? null : timeLine(match, now);
  const scored = result !== null;
  return (
    <li className="sched-row" data-us={side !== null}>
      <div className="sched-top">
        {linked ? (
          <Link className="sched-label" to={`/matches/${match.key}`}>
            {label}
          </Link>
        ) : (
          <span className="sched-label">{label}</span>
        )}
        {side && (
          <span className="sched-ours">
            Our match
            {outcome && <span className="sr-only">, we {outcome}</span>}
          </span>
        )}
        {result && <span className="sched-result">{result}</span>}
        {time && <span className="secondary">{time}</span>}
      </div>
      <AllianceLine
        side="Red"
        teams={match.red}
        us={us}
        score={scored ? match.redScore : undefined}
        won={winner === "Red"}
      />
      <AllianceLine
        side="Blue"
        teams={match.blue}
        us={us}
        score={scored ? match.blueScore : undefined}
        won={winner === "Blue"}
      />
    </li>
  );
}

function Group(props: {
  id: string;
  title: string;
  empty: string;
  matches: ScheduledMatch[];
  us: number | null;
  now: Date;
  linked: boolean;
}) {
  const { id, title, empty, matches, ...row } = props;
  return (
    <section className="sched-group" aria-labelledby={id}>
      <h2 id={id}>
        {title} <span className="sched-count">{matches.length}</span>
      </h2>
      {matches.length === 0 ? (
        <p className="secondary">{empty}</p>
      ) : (
        <ol className="plain sched-list">
          {matches.map((m) => (
            <MatchRow key={m.key} match={m} {...row} />
          ))}
        </ol>
      )}
    </section>
  );
}

function Message(props: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="sched-empty">
      <p>{props.children}</p>
      {props.action && <div className="actions">{props.action}</div>}
    </div>
  );
}

export function Schedule() {
  const data = useScoutData();
  const roles = useRoles();
  const team = useMyTeam();
  const online = useOnline();
  const [scope, setScope] = useState<Scope>("all");
  const linked = roles.status === "ready" && canOpenMatchPage(roles.roles);
  const lead = roles.status === "ready" && isLead(roles.roles);
  const now = new Date();
  const fetchedAt = Date.parse(data.scheduleFetchedAt ?? "");
  const updated = Number.isNaN(fetchedAt)
    ? null
    : formatTime(fetchedAt / 1000, now);
  const onlyOurs = scope === "ours" && team !== null;
  const rows = splitSchedule(data.schedule, team, onlyOurs);

  const head = (
    <header className="sched-head">
      <h1>Schedule</h1>
      {data.eventKey !== "" && (
        <p className="secondary">
          {data.eventKey}
          {updated && `, schedule updated ${updated}`}
        </p>
      )}
      {!online && (
        <p className="notice-soft">
          Offline.{" "}
          {updated
            ? `Showing the schedule from ${updated}.`
            : "No saved schedule on this device."}
        </p>
      )}
    </header>
  );

  if (data.eventKey === "") {
    return (
      <div className="sched">
        {head}
        <Message
          action={
            <Link className="btn primary" to="/settings?s=event">
              Open Settings
            </Link>
          }
        >
          No event is set. Pick your event to see its match schedule.
        </Message>
      </div>
    );
  }

  if (data.schedule.length === 0) {
    const waiting =
      data.scheduleStatus === "loading" || data.scheduleStatus === "none";
    const failed = data.scheduleStatus === "failed";
    return (
      <div className="sched">
        {head}
        {waiting ? (
          <Message>Loading the match schedule.</Message>
        ) : (
          <Message
            action={
              <button
                type="button"
                className={failed ? "btn primary" : "btn"}
                onClick={() => void data.refreshSchedule()}
              >
                {failed ? "Try again" : "Refresh"}
              </button>
            }
          >
            {failed
              ? "The match schedule could not be loaded. Check the connection and try again."
              : `The match schedule for ${data.eventKey} is not out yet.`}
          </Message>
        )}
      </div>
    );
  }

  return (
    <div className="sched">
      {head}
      {lead && <PredictionLine />}
      {team !== null && (
        <FilterChips<Scope>
          label="Show matches"
          value={scope}
          onPick={setScope}
          options={[
            { key: "all", text: "All matches" },
            { key: "ours", text: `Team ${team} only` },
          ]}
        />
      )}
      <Group
        id="sched-up"
        title="Upcoming"
        empty={
          onlyOurs
            ? `No matches left for team ${team}.`
            : "No matches are left on the schedule."
        }
        matches={rows.upcoming}
        us={team}
        now={now}
        linked={linked}
      />
      <Group
        id="sched-played"
        title="Played"
        empty={
          onlyOurs
            ? `Team ${team} has not played yet.`
            : "No match has been played yet."
        }
        matches={rows.played}
        us={team}
        now={now}
        linked={linked}
      />
    </div>
  );
}
