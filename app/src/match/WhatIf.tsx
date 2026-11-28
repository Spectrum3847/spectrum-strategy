import { useId, useMemo, useState } from "react";
import type { EventEntry, PitEntry } from "../data/parse";
import { parseTeamNumber } from "../now/myTeam";
import type { ScoutConfig } from "../scout/config";
import { TeamLink } from "../ui/TeamLink";
import { buildRobots, epaTotal, scoutedTotal } from "./robots";
import { readyTeams, scoutedWinChance } from "./whatIf";

const slotNames = ["red-1", "red-2", "red-3", "blue-1", "blue-2", "blue-3"];
const points = (n: number | null) => (n === null ? "--" : n.toFixed(1));

export function WhatIf({
  red,
  blue,
  config,
  pitConfig,
  entries,
  pit,
  nicknames,
  epa,
}: {
  red: number[];
  blue: number[];
  config: ScoutConfig;
  pitConfig: ScoutConfig;
  entries: EventEntry[];
  pit: PitEntry[];
  nicknames: Map<number, string>;
  epa: Record<number, number> | null;
}) {
  const start = useMemo(
    () => [...red, ...blue].map((t) => String(t)),
    [red, blue],
  );
  const [slots, setSlots] = useState(start);
  const id = useId();
  const set = (i: number, value: string) =>
    setSlots((s) => s.map((v, at) => (at === i ? value : v)));
  const teams = useMemo(() => readyTeams(slots), [slots]);
  const changed = slots.some((v, i) => v !== start[i]);

  const rows = useMemo(
    () =>
      teams
        ? buildRobots({
            config,
            pitConfig,
            matchKey: "",
            red: teams.red,
            blue: teams.blue,
            entries,
            pit,
            nicknames,
            epa,
          })
        : [],
    [teams, config, pitConfig, entries, pit, nicknames, epa],
  );
  const chance = teams
    ? scoutedWinChance(teams.red, teams.blue, entries)
    : null;

  return (
    <div className="whatif">
      <p className="secondary">
        Change any of the six teams to see how the prediction moves. Nothing is
        saved.
      </p>
      <div className="whatif-sides">
        {(["Red", "Blue"] as const).map((name, side) => (
          <fieldset
            key={name}
            className="whatif-side"
            data-alliance={name.toLowerCase()}
          >
            <legend className="tag" data-alliance={name.toLowerCase()}>
              {name}
            </legend>
            {[0, 1, 2].map((n) => {
              const i = side * 3 + n;
              const valid = parseTeamNumber(slots[i] ?? "") !== null;
              return (
                <div key={i} className="whatif-slot">
                  <label className="label" htmlFor={`${id}-${i}`}>
                    {`${name} team ${n + 1}`}
                  </label>
                  <input
                    id={`${id}-${i}`}
                    className="input"
                    inputMode="numeric"
                    autoComplete="off"
                    value={slots[i] ?? ""}
                    aria-invalid={!valid}
                    onChange={(e) => set(i, e.target.value)}
                  />
                </div>
              );
            })}
          </fieldset>
        ))}
      </div>
      <button
        type="button"
        className="btn"
        disabled={!changed}
        onClick={() => setSlots(start)}
      >
        Reset to this match
      </button>

      {teams === null || chance === null ? (
        <p className="secondary" role="status">
          Enter a team number in all six boxes to see a prediction.
        </p>
      ) : (
        <>
          <div className="match-scroll">
            <table className="match-table match-predict">
              <caption className="sr-only">
                Predicted score per alliance for the chosen teams
              </caption>
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
                  <th scope="row">Win chance from scouting</th>
                  <td>
                    {chance.red === null
                      ? "--"
                      : `${Math.round(chance.red * 100)}%`}
                  </td>
                  <td>
                    {chance.red === null
                      ? "--"
                      : `${100 - Math.round(chance.red * 100)}%`}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          {chance.red === null && (
            <p className="secondary">
              Not enough scouted data for a win chance. Each team needs 3 or
              more scout entries. Short: {chance.missing.join(", ")}.
            </p>
          )}
          <div className="match-scroll">
            <table className="match-table">
              <caption className="sr-only">Each chosen team</caption>
              <thead>
                <tr>
                  <th scope="col">Team</th>
                  <th scope="col">Auto</th>
                  <th scope="col">Teleop</th>
                  <th scope="col">Total</th>
                  <th scope="col">EPA</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr key={slotNames[i]} data-side={r.side}>
                    <th scope="row">
                      <TeamLink team={r.team} />
                    </th>
                    <td>{points(r.auto)}</td>
                    <td>{points(r.teleop)}</td>
                    <td>
                      {r.matches === 0
                        ? "--"
                        : points((r.auto ?? 0) + (r.teleop ?? 0))}
                    </td>
                    <td>{points(r.epa)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="secondary">
            From scouting adds each robot&apos;s typical auto and teleop. A
            robot nobody scouted adds 0. Win chance uses only this event&apos;s
            scout entries.
          </p>
        </>
      )}
    </div>
  );
}
