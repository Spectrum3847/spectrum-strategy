import type { ReactNode } from "react";
import { Link, Navigate } from "react-router";
import {
  canOpenMatchPage,
  isLead,
  isMentorOnly,
  landingFor,
  readsLeadPages,
} from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { Coverage, LastMatch, NextMatchExtras } from "../now/LeadSections";
import { lastResult } from "../now/lead";
import { formatTime } from "../now/matches";
import { useMyTeam } from "../now/myTeam";
import { LaterMatches, NextMatch, RankRecord, Scouting } from "../now/sections";
import { buildNow, lastPlayedQual, nextShift } from "../now/summary";
import { useRank } from "../now/useRank";
import { useScoutData } from "../scout/ScoutData";
import { useOnline } from "../ui/useOnline";

function Empty({
  children,
  action,
}: {
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="now-empty">
      <p>{children}</p>
      {action && <div className="actions">{action}</div>}
    </div>
  );
}

const settingsLink = (label: string, section: "event" | "device") => (
  <Link className="btn primary" to={`/settings?s=${section}`}>
    {label}
  </Link>
);

export function Now() {
  const data = useScoutData();
  const roles = useRoles();
  const team = useMyTeam();
  const online = useOnline();
  const rank = useRank(data.eventKey, team, data.scheduleFetchedAt);
  const ready = roles.status === "ready" ? roles : null;
  const lead = ready ? isLead(ready.roles) : false;
  const reader = ready ? readsLeadPages(ready.roles) : false;
  const mentor = ready ? isMentorOnly(ready.roles) : false;
  const now = new Date();
  const fetchedAt = Date.parse(data.scheduleFetchedAt ?? "");
  const updated = Number.isNaN(fetchedAt)
    ? null
    : formatTime(fetchedAt / 1000, now);

  const head = (
    <div className="now-head">
      <h1>Now</h1>
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
            ? `Showing the schedule from ${updated}. New scout entries stay on this device.`
            : "New scout entries stay on this device."}
        </p>
      )}
    </div>
  );

  if (data.eventKey === "") {
    return (
      <div className="now">
        {head}
        <Empty action={settingsLink("Open Settings", "event")}>
          No event is set. Pick your event to see your next match and scouting
          shift.
        </Empty>
      </div>
    );
  }

  if (data.schedule.length === 0) {
    const waiting =
      data.scheduleStatus === "loading" || data.scheduleStatus === "none";
    return (
      <div className="now">
        {head}
        {waiting ? (
          <Empty>Loading the match schedule.</Empty>
        ) : data.scheduleStatus === "failed" ? (
          <Empty
            action={
              <button
                type="button"
                className="btn primary"
                onClick={() => void data.refreshSchedule()}
              >
                Try again
              </button>
            }
          >
            The match schedule could not be loaded. Check the connection and try
            again.
          </Empty>
        ) : (
          <Empty
            action={
              <button
                type="button"
                className="btn"
                onClick={() => void data.refreshSchedule()}
              >
                Refresh
              </button>
            }
          >
            The match schedule for {data.eventKey} is not out yet.
          </Empty>
        )}
      </div>
    );
  }

  const summary = team === null ? null : buildNow(data.schedule, team);
  const shift = nextShift(
    data.shifts,
    ready?.identityUids ?? [],
    lastPlayedQual(data.schedule),
  );
  const showShift = mentor ? false : lead ? shift.status === "next" : true;
  const prep =
    ready && canOpenMatchPage(ready.roles) ? { primary: reader } : null;
  const scouting = showShift && <Scouting shift={shift} primary={!lead} />;
  const brief = ready
    ? landingFor(
        ready.roles,
        summary?.state === "ready" && summary.next
          ? summary.next.match.key
          : null,
      )
    : null;
  if (brief !== null) return <Navigate to={brief} replace />;

  let match: ReactNode;
  if (team === null || summary === null) {
    match = (
      <Empty action={settingsLink("Set team number", "device")}>
        Set your team number in Settings to see your next match.
      </Empty>
    );
  } else if (summary.state === "not-on-schedule") {
    match = (
      <Empty>
        Team {team} is not on the schedule for {data.eventKey}.
      </Empty>
    );
  } else if (summary.state === "ready" && summary.next === null) {
    match = (
      <Empty>
        {summary.scheduleDone
          ? `No matches are left on the schedule. Team ${team} played ${summary.playedCount}.`
          : `All ${summary.totalCount} of Team ${team}'s scheduled matches are played. Playoff matches appear here once The Blue Alliance posts them.`}
      </Empty>
    );
  } else if (summary.state === "ready" && summary.next) {
    match = (
      <NextMatch
        next={summary.next}
        team={team}
        now={now}
        prep={prep}
        extra={
          reader && (
            <NextMatchExtras
              matchKey={summary.next.match.key}
              red={summary.next.match.red}
              blue={summary.next.match.blue}
              eventKey={data.eventKey}
            />
          )
        }
      />
    );
  }

  const readySummary = summary?.state === "ready" ? summary : null;
  const last = reader && team !== null ? lastResult(data.schedule, team) : null;
  return (
    <div className="now">
      {head}
      {!lead && scouting}
      {match}
      {lead && scouting}
      {readySummary && team !== null && (
        <>
          <RankRecord rank={rank} summary={readySummary} now={now} />
          {last && <LastMatch result={last} link={prep !== null} />}
          {lead && (
            <Coverage schedule={data.schedule} eventKey={data.eventKey} />
          )}
          <LaterMatches
            later={readySummary.later}
            team={team}
            now={now}
            linkMatches={prep !== null}
          />
        </>
      )}
    </div>
  );
}
