import { matchLabel } from "../data/matchKey";
import type { EventMatch } from "../data/tbaEvent";
import { PickedMark } from "../picks/PickedMark";
import { formatStat } from "../team/format";
import { TeamLink } from "../ui/TeamLink";
import type { Forecast } from "./outside";
import {
  epaTotal,
  type RobotRow,
  type Side,
  scoutedInMatch,
  scoutedTotal,
} from "./robots";
import { conflictMessage, type StartConflict } from "./startConflicts";
import type { Outside } from "./useOutside";

const sideName: Record<Side, string> = { red: "Red", blue: "Blue" };
const cell = (n: number | null) => (n === null ? "--" : formatStat(n));
const points = (n: number | null) => (n === null ? "--" : n.toFixed(1));

function SideTag({ side }: { side: Side }) {
  return (
    <span className="tag" data-alliance={side}>
      {sideName[side]}
    </span>
  );
}

function Alliances({ rows, us }: { rows: RobotRow[]; us: number | null }) {
  return (
    <div className="match-alliances">
      {(["red", "blue"] as const).map((side) => (
        <div className="alliance" key={side}>
          <SideTag side={side} />
          <ul className="plain alliance-teams">
            {rows
              .filter((r) => r.side === side)
              .map((r) => (
                <li key={r.team} data-us={r.team === us}>
                  <TeamLink team={r.team} />
                  {r.team === us && <span className="us">us</span>}
                  <PickedMark team={r.team} />
                  {r.nickname !== "" && (
                    <span className="secondary">{r.nickname}</span>
                  )}
                </li>
              ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

function StatTable({ rows, us }: { rows: RobotRow[]; us: number | null }) {
  return (
    <div className="match-scroll">
      <table className="match-table">
        <caption className="sr-only">Scouted stats for the six robots</caption>
        <thead>
          <tr>
            <th scope="col">Team</th>
            <th scope="col">Robot type</th>
            <th scope="col">Auto</th>
            <th scope="col">Max auto</th>
            <th scope="col">Teleop</th>
            <th scope="col">IQM fuel</th>
            <th scope="col">Max teleop</th>
            <th scope="col">Climb</th>
            <th scope="col">Auto climb</th>
            <th scope="col">Scouted</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.team} data-side={r.side}>
              <th scope="row">
                <TeamLink team={r.team} />
                {r.team === us && <span className="us">us</span>}
              </th>
              <td className="match-type">{r.robotType || "--"}</td>
              <td>{cell(r.auto)}</td>
              <td>{cell(r.maxAuto)}</td>
              <td>{cell(r.teleop)}</td>
              <td>{cell(r.iqmFuel)}</td>
              <td>{cell(r.maxTeleop)}</td>
              <td>{r.climb || "--"}</td>
              <td>{r.autoClimb ? "Yes" : "--"}</td>
              <td>{r.matches}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function epaNotice(epa: Outside<Record<number, number>>): string | null {
  if (epa.data !== null && Object.keys(epa.data).length > 0) return null;
  if (epa.status === "ready") {
    return "Statbotics has no EPA for this event, which is common for offseason events. Expected points show --.";
  }
  if (epa.status === "failed") {
    return "Statbotics could not be reached and nothing is saved on this device. Expected points show --.";
  }
  return "Loading expected points from Statbotics.";
}

export function Prediction({
  rows,
  epa,
  forecast,
  forecasts,
}: {
  rows: RobotRow[];
  epa: Outside<Record<number, number>>;
  forecast: Forecast | null;
  forecasts: Outside<Record<string, Forecast>>;
}) {
  const scouted = rows.some((r) => r.matches > 0);
  const notice = epaNotice(epa);
  return (
    <>
      <div className="match-scroll">
        <table className="match-table match-predict">
          <caption className="sr-only">Predicted score per alliance</caption>
          <thead>
            <tr>
              <th scope="col">Source</th>
              <th scope="col">Red</th>
              <th scope="col">Blue</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <th scope="row">Expected points (Statbotics EPA)</th>
              <td>{points(epaTotal(rows, "red"))}</td>
              <td>{points(epaTotal(rows, "blue"))}</td>
            </tr>
            <tr>
              <th scope="row">From scouting</th>
              <td>{points(scoutedTotal(rows, "red"))}</td>
              <td>{points(scoutedTotal(rows, "blue"))}</td>
            </tr>
            <tr>
              <th scope="row">Forecast (The Blue Alliance)</th>
              <td>{forecast ? points(forecast.redScore) : "--"}</td>
              <td>{forecast ? points(forecast.blueScore) : "--"}</td>
            </tr>
            {forecast && (
              <tr>
                <th scope="row">Win chance (The Blue Alliance)</th>
                <td>{Math.round(forecast.redWin * 100)}%</td>
                <td>{Math.round((1 - forecast.redWin) * 100)}%</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <ul className="plain match-notes secondary">
        {notice && <li>{notice}</li>}
        {!scouted && <li>No robot in this match has been scouted yet.</li>}
        {forecast === null && (
          <li>
            {forecasts.status === "failed"
              ? "The Blue Alliance forecast could not be loaded."
              : "The Blue Alliance has no forecast for this match yet."}
          </li>
        )}
        {scouted && (
          <li>
            From scouting adds each robot's typical auto and teleop. A robot
            nobody scouted adds 0.
          </li>
        )}
      </ul>
    </>
  );
}

export function Result({
  match,
  rows,
}: {
  match: EventMatch;
  rows: RobotRow[];
}) {
  const winner =
    match.winner === "red"
      ? "Red won"
      : match.winner === "blue"
        ? "Blue won"
        : "Tied";
  return (
    <>
      <p className="match-winner">{winner}</p>
      <ul className="plain match-result">
        {(["red", "blue"] as const).map((side) => {
          const seen = scoutedInMatch(rows, side);
          const official = side === "red" ? match.redScore : match.blueScore;
          return (
            <li key={side}>
              <SideTag side={side} />
              <span>Official {official ?? "--"}</span>
              <span>
                Scouted {points(seen.total)} from {seen.robots} of {seen.of}{" "}
                robots
              </span>
            </li>
          );
        })}
      </ul>
      <p className="secondary">
        Scouted is the summed score of the scouted robots in this match, not
        official points. A low figure usually means robots went unscouted.
      </p>
    </>
  );
}

export function Comments({ rows }: { rows: RobotRow[] }) {
  const withComment = rows.filter((r) => r.comment !== null);
  if (withComment.length === 0) {
    return <p className="secondary">No scout comments for these robots yet.</p>;
  }
  return (
    <ul className="plain match-comments">
      {withComment.map((r) => {
        const c = r.comment;
        if (!c) return null;
        const from = [
          c.scoutName,
          c.matchKey ? matchLabel(c.matchKey) : "",
        ].filter((p) => p !== "");
        return (
          <li key={r.team} data-side={r.side}>
            <p className="match-comment-team">
              <TeamLink team={r.team} />
              {r.nickname !== "" && (
                <span className="secondary">{r.nickname}</span>
              )}
            </p>
            <p>{c.text}</p>
            {from.length > 0 && <p className="secondary">{from.join(", ")}</p>}
          </li>
        );
      })}
    </ul>
  );
}

export function UnscoutedNotice({ rows }: { rows: RobotRow[] }) {
  const missing = rows.filter((r) => r.matches === 0);
  if (missing.length === 0) return null;
  return (
    <p className="notice-soft match-unscouted" role="status">
      Not scouted yet:{" "}
      {missing.map((r, i) => (
        <span key={r.team}>
          {i > 0 && ", "}
          <TeamLink team={r.team} />
        </span>
      ))}
    </p>
  );
}

export function StartConflictNotice({
  conflicts,
}: {
  conflicts: StartConflict[];
}) {
  if (conflicts.length === 0) return null;
  return (
    <div className="notice" role="status">
      <p className="label">Start position clash</p>
      <ul className="plain start-conflicts">
        {conflicts.map((c) => (
          <li key={c.position}>{conflictMessage(c)}</li>
        ))}
      </ul>
    </div>
  );
}

export { Alliances, StatTable };
