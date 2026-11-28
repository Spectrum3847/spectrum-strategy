import { useMemo, useState } from "react";
import { Link } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { matchLabel, matchPath } from "../data/matchKey";
import { FilterChips } from "../forms/ListParts";
import { ModeTabs } from "../forms/ModeTabs";
import { explainResult } from "../match/explain";
import { useScoutData } from "../scout/ScoutData";
import { useTrainingSession } from "../training/session";
import {
  type Check,
  type CheckRow,
  minBand,
  minMatches,
  offBy,
  type Source,
  verdict,
} from "./predictionCheck";
import { useOfficialCounts } from "./useAccuracyData";
import { usePredictionCheck } from "./usePredictionCheck";
import "./accuracy.css";

const sourceName: Record<Source, string> = {
  tba: "The Blue Alliance",
  scouting: "our scouting",
};

const percent = (n: number) => `${Math.round(n * 100)}%`;
const winner = (r: CheckRow) =>
  r.redScore === r.blueScore
    ? "Tied"
    : `${r.redScore > r.blueScore ? "Red" : "Blue"} won`;

function Rows({
  rows,
  reason,
  empty,
}: {
  rows: CheckRow[];
  reason(row: CheckRow): string;
  empty: string;
}) {
  if (rows.length === 0) return <p className="secondary">{empty}</p>;
  return (
    <ul className="plain pc-rows">
      {rows.map((r) => (
        <li key={r.key} data-right={r.right}>
          <div className="pc-top">
            <Link className="pc-label" to={matchPath(r.key)}>
              {matchLabel(r.key)}
            </Link>
            <span>
              {r.favourite === "red" ? "Red" : "Blue"} favoured at{" "}
              {percent(r.said)}
            </span>
            <span>
              {winner(r)} {r.redScore} to {r.blueScore}
            </span>
            <span className="pc-mark">
              {r.right === 1
                ? "Favourite won"
                : r.right === 0
                  ? "Favourite lost"
                  : "Tie"}
            </span>
          </div>
          {r.predRed !== null && r.predBlue !== null && (
            <p className="secondary">
              Predicted {Math.round(r.predRed)} to {Math.round(r.predBlue)}
            </p>
          )}
          <p className="secondary">{reason(r)}</p>
        </li>
      ))}
    </ul>
  );
}

function Summary({ check, source }: { check: Check; source: Source }) {
  const lean =
    check.lean === null
      ? null
      : Math.abs(check.lean) < 10
        ? "no clear lean"
        : check.lean < 0
          ? "predicts too low"
          : "predicts too high";
  return (
    <ul className="plain pc-tiles">
      <li>
        <span className="secondary">Favourite won</span>
        <strong>{percent(check.right / check.n)}</strong>
        <span className="secondary">
          {check.right} of {check.n} matches
        </span>
      </li>
      {check.error !== null && check.lean !== null && (
        <>
          <li>
            <span className="secondary">Score miss</span>
            <strong>{Math.round(check.error)}</strong>
            <span className="secondary">points per alliance, on average</span>
          </li>
          <li>
            <span className="secondary">Lean</span>
            <strong>
              {check.lean >= 0 ? "+" : "-"}
              {Math.abs(Math.round(check.lean))}
            </strong>
            <span className="secondary">{lean}</span>
          </li>
        </>
      )}
      {source === "scouting" && (
        <li>
          <span className="secondary">Score miss</span>
          <strong>--</strong>
          <span className="secondary">
            Scouted fuel is not official points, so there is no score to check
          </span>
        </li>
      )}
    </ul>
  );
}

function Bands({ check }: { check: Check }) {
  const shown = check.bands.filter((b) => b.n > 0);
  return (
    <div className="acc-scroll">
      <table className="acc-table">
        <caption className="sr-only">
          How often the favourite won, by the chance given to it
        </caption>
        <thead>
          <tr>
            <th scope="col">Chance given</th>
            <th scope="col" className="acc-num">
              Matches
            </th>
            <th scope="col" className="acc-num">
              Favourite won
            </th>
            <th scope="col">Verdict</th>
          </tr>
        </thead>
        <tbody>
          {shown.map((b) => (
            <tr key={b.label}>
              <th scope="row">{b.label}</th>
              <td className="acc-num">{b.n}</td>
              <td className="acc-num">{percent(b.won)}</td>
              <td>{verdict(b)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function PredictionCheck() {
  const auth = useAuth();
  const training = useTrainingSession() !== null;
  const { config } = useScoutData();
  const { eventKey, ready, checks, firstWithMatches } = usePredictionCheck();
  const entries = useCorrectedEntries(eventKey);
  const official = useOfficialCounts(
    eventKey,
    auth.status === "signed-in" && !training,
  );
  const [picked, setPicked] = useState<Source | null>(null);
  const source = picked ?? firstWithMatches;
  const check = checks[source];

  const reasons = useMemo(() => {
    const out = new Map<string, string>();
    for (const row of [...check.ours, ...check.misses]) {
      if (out.has(row.key)) continue;
      const why = explainResult({
        config,
        matchKey: row.key,
        red: row.red,
        blue: row.blue,
        redScore: row.redScore,
        blueScore: row.blueScore,
        entries: entries.items,
        breakdown: official.alliances,
        redWin: row.redWin,
        chanceFrom: sourceName[source],
        tba: null,
        trex: [],
      });
      out.set(row.key, why.causes[0] ?? "Close to the forecast.");
    }
    return out;
  }, [check, config, entries.items, official.alliances, source]);
  const reason = (row: CheckRow) => reasons.get(row.key) ?? "";

  return (
    <div className="accuracy">
      <ModeTabs />
      <header className="acc-head">
        <h1>Prediction check</h1>
        <Link className="btn" to="/scout/accuracy">
          Scouter accuracy
        </Link>
      </header>
      <p className="acc-intro">
        How well the predictions did at this event. For every played match, this
        takes the prediction as it stood before the match and sets it beside the
        result. Our scouting uses only the matches before each one. The Blue
        Alliance forecast is its own pre-match one.
      </p>
      <FilterChips<Source>
        label="Prediction source"
        value={source}
        onPick={setPicked}
        options={[
          { key: "tba", text: "The Blue Alliance" },
          { key: "scouting", text: "Our scouting" },
        ]}
      />
      {eventKey === "" ? (
        <p className="secondary">Choose an event in Settings first.</p>
      ) : check.n === 0 ? (
        <p className="secondary">
          {ready
            ? `No played match has a prediction from ${sourceName[source]} yet.`
            : "Loading the event."}
        </p>
      ) : (
        <>
          {!check.enough && (
            <div className="notice-soft" role="status">
              Too early to judge: {check.n} played match
              {check.n === 1 ? "" : "es"}. Wait for {minMatches} or more.
            </div>
          )}
          <Summary check={check} source={source} />
          <section className="pc-section" aria-labelledby="pc-bands">
            <h2 id="pc-bands">Can the win chance be trusted?</h2>
            <Bands check={check} />
            <p className="secondary">
              A row with fewer than {minBand} matches is too few to tell. A row
              is off when the favourite won more than {Math.round(offBy * 100)}{" "}
              points more or less often than the chance given.
            </p>
          </section>
          <section className="pc-section" aria-labelledby="pc-ours">
            <h2 id="pc-ours">Our matches</h2>
            <Rows
              rows={check.ours}
              reason={reason}
              empty="No played match of ours has a prediction yet."
            />
          </section>
          {source === "tba" && (
            <section className="pc-section" aria-labelledby="pc-misses">
              <h2 id="pc-misses">Biggest misses</h2>
              <Rows
                rows={check.misses}
                reason={reason}
                empty="No scores to compare yet."
              />
              <p className="secondary">
                Worth a look for breakdowns, defense or a robot that changed.
                One big miss is not a reason to distrust the whole forecast.
              </p>
            </section>
          )}
        </>
      )}
    </div>
  );
}
