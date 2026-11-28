import { useMemo, useState } from "react";
import { Link } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { matchLabel, matchPath } from "../data/matchKey";
import { ModeTabs } from "../forms/ModeTabs";
import { useScoutData } from "../scout/ScoutData";
import { useTrainingSession } from "../training/session";
import { TeamLink } from "../ui/TeamLink";
import { MappingSection } from "./MappingSection";
import {
  type AccuracyReport,
  bandLabel,
  buildReport,
  formatMiss,
  minRobots,
  type ScoutScore,
} from "./opr";
import { season } from "./season";
import {
  type Official,
  type OfficialProblem,
  useOfficialCounts,
} from "./useAccuracyData";
import "./accuracy.css";

const problemText: Record<OfficialProblem, string> = {
  "no-key": "No Blue Alliance key is available on this device yet.",
  rejected:
    "The Blue Alliance rejected the team key. Ask an admin to replace it in the shared app config.",
  "not-found":
    "The Blue Alliance has no matches for this event key. Check the event in Settings.",
  unreachable: "The Blue Alliance could not be reached.",
};

const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? "" : "s"}`;

const timeOf = (iso: string | null) => {
  const ms = iso ? Date.parse(iso) : Number.NaN;
  return Number.isNaN(ms)
    ? null
    : new Date(ms).toLocaleTimeString([], {
        hour: "numeric",
        minute: "2-digit",
      });
};

function Coverage({
  report,
  official,
}: {
  report: AccuracyReport;
  official: Official;
}) {
  const capture = report.averageCapture;
  const stamp = timeOf(official.fetchedAt);
  const lines = [
    `${plural(report.equations, "alliance")} used`,
    capture !== null
      ? `Scouts record ${Math.round(capture * 100)}% of the official ${season.pieceName} on average`
      : null,
    report.incomplete > 0
      ? `${plural(report.incomplete, "alliance")} left out: a robot was not scouted`
      : null,
    report.skipped > 0
      ? `${plural(report.skipped, "alliance")} left out: a robot has two entries, or an entry has no scout name or count`
      : null,
    stamp ? `Official counts from ${stamp}` : null,
  ].filter((line): line is string => line !== null);
  return (
    <ul className="acc-coverage secondary">
      {lines.map((line) => (
        <li key={line}>{line}</li>
      ))}
    </ul>
  );
}

function Drill({ score, id }: { score: ScoutScore; id: string }) {
  return (
    <tr id={id}>
      <td colSpan={4} className="acc-drill-cell">
        <div className="acc-scroll">
          <table className="acc-table acc-inner">
            <caption className="sr-only">Matches behind {score.name}</caption>
            <thead>
              <tr>
                <th scope="col">Match</th>
                <th scope="col">Robot</th>
                <th scope="col">Side</th>
                <th scope="col">Counted</th>
                <th scope="col">Alliance scouted</th>
                <th scope="col">Official</th>
                <th scope="col">Alliance miss</th>
              </tr>
            </thead>
            <tbody>
              {score.used.map((u) => (
                <tr key={`${u.matchKey}-${u.alliance}-${u.team}`}>
                  <th scope="row">
                    <Link to={matchPath(u.matchKey)}>
                      {matchLabel(u.matchKey)}
                    </Link>
                  </th>
                  <td>
                    <TeamLink team={u.team} />
                  </td>
                  <td>{u.alliance === "red" ? "Red" : "Blue"}</td>
                  <td>{u.count}</td>
                  <td>{u.scouted}</td>
                  <td>{u.official}</td>
                  <td>{formatMiss(u.official - u.scouted)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </td>
    </tr>
  );
}

function ScoutRows({ score }: { score: ScoutScore }) {
  const [open, setOpen] = useState(false);
  const id = `acc-${score.name.replace(/\W+/g, "-")}`;
  return (
    <>
      <tr className="acc-row" data-enough={score.enough}>
        <th scope="row">
          <button
            type="button"
            className="acc-toggle"
            aria-expanded={open}
            aria-controls={open ? id : undefined}
            onClick={() => setOpen(!open)}
          >
            {score.name}
          </button>
        </th>
        <td className="acc-num">{formatMiss(score.miss)}</td>
        <td className="acc-num">{score.robots}</td>
        <td>
          {score.enough ? (
            <span className="acc-band" data-band={score.band}>
              {bandLabel[score.band]}
            </span>
          ) : (
            <span className="acc-band" data-band="few">
              Not enough data
            </span>
          )}
        </td>
      </tr>
      {open && <Drill score={score} id={id} />}
    </>
  );
}

function ScoutTable({ report }: { report: AccuracyReport }) {
  return (
    <div className="acc-scroll">
      <table className="acc-table">
        <caption className="sr-only">
          Scouts by estimated {season.pieceName} missed per robot per match
        </caption>
        <thead>
          <tr>
            <th scope="col">Scout</th>
            <th scope="col" className="acc-num">
              Estimate
            </th>
            <th scope="col" className="acc-num">
              Robots
            </th>
            <th scope="col">Status</th>
          </tr>
        </thead>
        <tbody>
          {report.scouts.map((score) => (
            <ScoutRows key={score.name.toLowerCase()} score={score} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Body({
  eventKey,
  training,
  official,
  entriesReady,
  report,
}: {
  eventKey: string;
  training: boolean;
  official: Official;
  entriesReady: boolean;
  report: AccuracyReport;
}) {
  if (eventKey === "") {
    return <p className="secondary">Choose an event in Settings first.</p>;
  }
  if (training) {
    return (
      <p className="secondary">
        Scouter accuracy is not available in training mode.
      </p>
    );
  }
  const have = official.alliances.length > 0;
  if (!have) {
    if (official.status === "failed") {
      return (
        <div className="notice" role="alert">
          {official.problem ? problemText[official.problem] : ""} Nothing is
          saved on this device yet. Try Refresh when the connection is back.
        </div>
      );
    }
    if (official.status === "ready") {
      return (
        <p className="secondary">
          No played match has an official {season.pieceName} count yet. The Blue
          Alliance posts it after each match, in the score breakdown (
          {season.breakdownLabel}).
        </p>
      );
    }
    return <p className="secondary">Loading the official counts.</p>;
  }
  if (!entriesReady) return <p className="secondary">Loading scout entries.</p>;
  return (
    <>
      {official.status === "failed" && official.problem && (
        <div className="notice" role="alert">
          Refresh failed, so the official counts may be out of date.{" "}
          {problemText[official.problem]}
        </div>
      )}
      <Coverage report={report} official={official} />
      {report.equations === 0 ? (
        <p className="secondary">
          No complete alliances yet. An alliance counts once each of its three
          robots in a played match has one scout entry with a scout name and a{" "}
          {season.pieceName} count.
        </p>
      ) : (
        <ScoutTable report={report} />
      )}
    </>
  );
}

export function Accuracy() {
  const auth = useAuth();
  const { eventKey } = useScoutData();
  const training = useTrainingSession() !== null;
  const signedIn = auth.status === "signed-in";
  const entries = useCorrectedEntries(eventKey);
  const official = useOfficialCounts(eventKey, signedIn && !training);
  const report = useMemo(
    () => buildReport(entries.items, official.alliances),
    [entries.items, official.alliances],
  );
  return (
    <div className="accuracy">
      <ModeTabs />
      <header className="acc-head">
        <h1>Scouter accuracy</h1>
        <Link className="btn" to="/scout/accuracy/predictions">
          Prediction check
        </Link>
        <button
          type="button"
          className="btn"
          disabled={
            training || eventKey === "" || official.status === "loading"
          }
          onClick={official.refresh}
        >
          {official.status === "loading" ? "Refreshing" : "Refresh"}
        </button>
      </header>
      <p className="acc-intro">
        For coaching, not blame. Each estimate is the {season.pieceName} a scout
        misses per robot per match, worked out from how scouted alliance totals
        compare with the official count. Plus means under-counting, minus means
        over-counting. Within 4 is OK, within 12 is worth a check-in, and more
        than 12 is worth coaching. It steadies as the event goes on, and a scout
        with fewer than {minRobots} robots is marked not enough data. It uses
        each scout's own entry, before any lead correction.
      </p>
      {entries.failed && (
        <div className="notice" role="alert">
          The scout entries could not be read, so the list may be incomplete.
        </div>
      )}
      <Body
        eventKey={eventKey}
        training={training}
        official={official}
        entriesReady={entries.ready}
        report={report}
      />
      <MappingSection />
    </div>
  );
}
