import { type ReactNode, useMemo } from "react";
import { Link } from "react-router";
import { useEventEntries } from "../data/entries";
import { useFormConfig, usePitEntries } from "../data/useCollections";
import { Prediction } from "../match/MatchTab";
import { buildRobots } from "../match/robots";
import { useBriefs } from "../match/useBriefs";
import { useEpa, useForecasts } from "../match/useOutside";
import { useOutbox } from "../outbox/useOutbox";
import { useScoutData } from "../scout/ScoutData";
import type { ScheduledMatch } from "../scout/schedule";
import { TeamLink } from "../ui/TeamLink";
import {
  type BriefStatus,
  briefStatus,
  coverage,
  coverageWindow,
  type LastResult,
} from "./lead";
import { Section } from "./sections";
import "../match/match.css";

const briefText: Record<BriefStatus, string> = {
  ready: "Ready",
  draft: "Draft, not marked ready yet",
  none: "No brief yet",
};

export function NextMatchExtras({
  matchKey,
  red,
  blue,
  eventKey,
}: {
  matchKey: string;
  red: number[];
  blue: number[];
  eventKey: string;
}) {
  const { config } = useScoutData();
  const entries = useEventEntries(eventKey);
  const pit = usePitEntries();
  const pitConfig = useFormConfig("pit");
  const epa = useEpa(eventKey);
  const forecasts = useForecasts(eventKey);
  const briefs = useBriefs();
  const rows = useMemo(
    () =>
      buildRobots({
        config,
        pitConfig,
        matchKey,
        red,
        blue,
        entries: entries.items,
        pit: pit.items,
        nicknames: new Map(),
        epa: epa.data,
      }),
    [
      config,
      pitConfig,
      matchKey,
      red,
      blue,
      entries.items,
      pit.items,
      epa.data,
    ],
  );
  const forecast =
    forecasts.data?.[matchKey] ?? forecasts.data?.[matchKey.toLowerCase()];

  const brief =
    briefs.failed && briefs.items.length === 0
      ? "Briefs could not be read."
      : !briefs.ready
        ? "Reading briefs."
        : briefText[briefStatus(briefs.items, eventKey, matchKey)];

  return (
    <>
      <h3>Predicted score</h3>
      {entries.failed && (
        <p className="notice-soft" role="status">
          Could not read the latest scout entries. The scouted figure may be
          incomplete.
        </p>
      )}
      <Prediction
        rows={rows}
        epa={epa}
        forecast={forecast ?? null}
        forecasts={forecasts}
      />
      <h3>Brief</h3>
      <p>{brief}</p>
    </>
  );
}

export function LastMatch({
  result,
  link,
}: {
  result: LastResult;
  link: boolean;
}) {
  const verb = { won: "Won", lost: "Lost", tied: "Tied" }[result.outcome];
  return (
    <Section id="last-h" title="Our last match">
      <p className="now-label">
        {link ? (
          <Link className="later-label" to={`/matches/${result.match.key}`}>
            {result.label}
          </Link>
        ) : (
          result.label
        )}
        <span className="now-away">
          {verb} {result.ours} to {result.theirs}
        </span>
      </p>
      <p className="secondary">
        We played{" "}
        <span className="tag" data-alliance={result.alliance.toLowerCase()}>
          {result.alliance}
        </span>
      </p>
    </Section>
  );
}

export function Coverage({
  schedule,
  eventKey,
}: {
  schedule: ScheduledMatch[];
  eventKey: string;
}) {
  const entries = useEventEntries(eventKey);
  const outbox = useOutbox();
  const result = useMemo(
    () => coverage(schedule, entries.items),
    [schedule, entries.items],
  );
  const mine = outbox.filter((i) => i.path.startsWith("scoutEntries/"));
  const unsent = mine.filter(
    (i) => i.status === "on-device" || i.status === "sending",
  ).length;
  const refused = mine.filter((i) => i.status === "refused").length;
  const unknown = entries.failed && entries.items.length === 0;

  let body: ReactNode;
  if (unknown) {
    body = <p>Could not read the scout entries, so coverage is unknown.</p>;
  } else if (!entries.ready) {
    body = <p className="secondary">Reading scout entries.</p>;
  } else if (result.through === null) {
    body = (
      <p className="secondary">
        No qualification match has been played yet, so there is nothing to
        check.
      </p>
    );
  } else if (result.gaps.length === 0) {
    body = (
      <p>
        Every robot in Q{result.from} to Q{result.through} has a scout entry.
      </p>
    );
  } else {
    body = (
      <>
        <p>
          {result.robots} {result.robots === 1 ? "robot has" : "robots have"} no
          scout entry in the last {coverageWindow} played qualification matches
          (Q{result.from} to Q{result.through}).
        </p>
        <ul className="plain gaps">
          {result.gaps.map((g) => (
            <li key={g.match.key}>
              <Link className="later-label" to={`/matches/${g.match.key}`}>
                {g.label}
              </Link>
              <span className="secondary">not scouted</span>
              {g.teams.map((t) => (
                <TeamLink key={t} team={t} />
              ))}
            </li>
          ))}
        </ul>
      </>
    );
  }

  return (
    <Section id="coverage-h" title="Scouting coverage">
      {entries.failed && !unknown && (
        <p className="notice-soft" role="status">
          Could not read the latest scout entries. This may be incomplete.
        </p>
      )}
      {body}
      {unsent > 0 && (
        <p>
          {unsent} scout {unsent === 1 ? "entry is" : "entries are"} on this
          device and not in the database yet.
        </p>
      )}
      {refused > 0 && (
        <p className="notice" role="status">
          The database refused {refused} scout{" "}
          {refused === 1 ? "entry" : "entries"} from this device.
        </p>
      )}
      {unsent + refused > 0 && (
        <div className="actions">
          <Link className="btn" to="/scout">
            Open Scout
          </Link>
        </div>
      )}
    </Section>
  );
}
