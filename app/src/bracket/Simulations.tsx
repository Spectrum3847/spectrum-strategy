import { useMemo, useState } from "react";
import type { Rounds } from "../picks/draft";
import type { Layout } from "../picks/pickList";
import { TeamLink } from "../ui/TeamLink";
import { type Robot, report, scenarios } from "./data";
import { model } from "./model";
import "./bracket.css";

function Report({
  teams,
  robots,
}: {
  teams: number[];
  robots: Map<number, Robot>;
}) {
  const r = report(teams, robots),
    format = (n: number | null) => (n === null ? "No data" : n.toFixed(1));
  if (!r.best.length) return <p>No scouted scores for this alliance.</p>;
  return (
    <div>
      <p>
        Expected score: {format(r.score)} · Auto: {format(r.auto)} · Teleop:{" "}
        {format(r.teleop)} · Climb: {format(r.climb)} · Driver skill:{" "}
        {format(r.driver)}
      </p>
      <p>
        Best scouted robots: {r.best.join(", ")}. Auto starts:{" "}
        {r.best
          .map((t) => `${t} ${robots.get(t)?.start || "unknown"}`)
          .join(" · ")}
      </p>
      {r.clashes.length > 0 && <p>Auto starts clash: {r.clashes.join(", ")}</p>}
      {r.incidents.map(([team, text]) => (
        <p key={team}>
          {team}: {text}
        </p>
      ))}
    </div>
  );
}
const blank = (cols: number) =>
  Array.from({ length: 8 }, () => Array<string>(cols).fill(""));
export function Simulations({
  ranking,
  official,
  rounds,
  us,
  layout,
  robots,
  eventKey,
}: {
  ranking: number[];
  official: number[];
  rounds: Rounds;
  us: number | null;
  layout: Layout | null;
  robots: Map<number, Robot>;
  eventKey: string;
}) {
  const key = `bracket-manual-${eventKey}`;
  const [grid, setGrid] = useState<string[][]>(() => {
    try {
      const saved: unknown = JSON.parse(localStorage.getItem(key) ?? "null");
      if (
        Array.isArray(saved) &&
        saved.length === 8 &&
        saved.every(
          (r) =>
            Array.isArray(r) && r.every((v: unknown) => typeof v === "string"),
        )
      )
        return saved as string[][];
    } catch {
    }
    return blank(rounds + 1);
  });
  const [selected, setSelected] = useState(0),
    [kept, setKept] = useState(true);
  const setManual = (next: string[][]) => {
    setGrid(next);
    try {
      localStorage.setItem(key, JSON.stringify(next));
      setKept(true);
    } catch {
      setKept(false);
    }
  };
  const runs = useMemo(
    () =>
      official.length >= 8
        ? scenarios(ranking, rounds, us, layout, robots)
        : [],
    [ranking, official, rounds, us, layout, robots],
  );
  const valid = (v: string) => /^\d+$/.test(v) && ranking.includes(Number(v));
  const teams = grid.map((row) => row.filter(valid).map(Number));
  const all = teams.flat(),
    complete =
      teams.every((row) => row.length >= 3) &&
      new Set(all).size === all.length &&
      grid.every((row) => row.every((v) => v === "" || valid(v)));
  const filled = complete ? JSON.stringify(teams) : "";
  const odds = useMemo(
    () =>
      filled === ""
        ? null
        : model(JSON.parse(filled) as number[][], robots).odds(1500).title,
    [filled, robots],
  );
  const headers = [
    "Captain",
    "First pick",
    "Second pick",
    ...(rounds === 3 ? ["Third pick"] : []),
  ];
  return (
    <div className="simulations">
      <h2>Alliance selection simulations</h2>
      <p>
        Six drafts use different priorities. Our alliance follows the pick list.
        Title chances use 1,500 simulated playoffs. Unscouted teams contribute
        zero points with estimated uncertainty.
      </p>
      {runs.length === 0 && (
        <p>An official ranking with at least eight teams is needed.</p>
      )}
      {runs.length > 0 && (
        <p>
          Our team is on an alliance in{" "}
          {runs.filter((run) => run.index >= 0).length} of {runs.length}{" "}
          scenarios.
        </p>
      )}
      {runs.map((run) => (
        <section key={run.name}>
          <h3>
            {run.name}
            {run === runs[0] && run.index >= 0 ? " · Best for us" : ""}
          </h3>
          <p className="secondary">
            {
              (
                {
                  Chalk: "Other captains pick by scouted score.",
                  "Consistency first":
                    "Other captains pick teams with the least variation in scouted scores.",
                  "Endgame first": "Other captains count climb points twice.",
                  "Auto first": "Other captains count auto points twice.",
                  "Unpredictable A":
                    "Other captains use a seeded variation of scouted scores.",
                  "Unpredictable B":
                    "Other captains use another seeded variation of scouted scores.",
                } as Record<string, string>
              )[run.name]
            }
          </p>
          <div className="simulation-table">
            <table>
              <thead>
                <tr>
                  <th scope="col">Alliance</th>
                  {headers.map((h) => (
                    <th scope="col" key={h}>
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {run.alliances.map((a, i) => (
                  <tr key={a.join("-")}>
                    <th scope="row">
                      {i + 1}
                      {i === run.index ? " (us)" : ""}
                    </th>
                    {headers.map((h, j) => (
                      <td key={h}>
                        {a[j] ? <TeamLink team={a[j]} /> : "No team"}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {run.index >= 0 ? (
            <>
              <p>
                Our title chance:{" "}
                {run.odds
                  ? `${Math.round(run.chance * 100)}%`
                  : "Not available"}
              </p>
              <Report teams={run.alliances[run.index] ?? []} robots={robots} />
            </>
          ) : (
            <p>We are not on an alliance in this scenario.</p>
          )}
          <button
            className="btn"
            type="button"
            onClick={() =>
              setManual(
                run.alliances.map((a) =>
                  headers.map((_, i) => a[i]?.toString() ?? ""),
                ),
              )
            }
          >
            Edit a copy
          </button>
        </section>
      ))}
      <section>
        <h2>Build your own</h2>
        <p>
          Enter teams to see the alliance report. Fill eight alliances with at
          least three different teams each for title chances. This table stays
          on this device.
        </p>
        <div className="actions">
          <button
            className="btn"
            type="button"
            onClick={() => setManual(blank(headers.length))}
          >
            Clear
          </button>
          <button
            className="btn"
            type="button"
            onClick={() =>
              setManual(
                blank(headers.length).map((row, i) => [
                  ranking[i]?.toString() ?? "",
                  ...row.slice(1),
                ]),
              )
            }
          >
            Fill captains
          </button>
        </div>
        {!kept && <p role="alert">This device could not save the table.</p>}
        <div className="simulation-table">
          <table>
            <thead>
              <tr>
                <th scope="col">Alliance</th>
                {headers.map((h) => (
                  <th scope="col" key={h}>
                    {h}
                  </th>
                ))}
                <th scope="col">Expected score and title</th>
              </tr>
            </thead>
            <tbody>
              {[1, 2, 3, 4, 5, 6, 7, 8].map((seed) => {
                const i = seed - 1;
                return (
                  <tr key={seed}>
                    <th scope="row">{i + 1}</th>
                    {headers.map((h, j) => {
                      const v = grid[i]?.[j] ?? "";
                      const duplicate =
                        v !== "" &&
                        all.filter((t) => t === Number(v)).length > 1;
                      return (
                        <td key={h}>
                          <input
                            type="text"
                            inputMode="numeric"
                            aria-label={`Alliance ${i + 1} ${h}`}
                            aria-invalid={v !== "" && (!valid(v) || duplicate)}
                            value={v}
                            onFocus={() => setSelected(i)}
                            onChange={(e) => {
                              const next = grid.map((row) => [...row]);
                              const row = next[i];
                              if (row) row[j] = e.target.value;
                              setManual(next);
                            }}
                          />
                        </td>
                      );
                    })}
                    <td>
                      {report(teams[i] ?? [], robots).score?.toFixed(1) ??
                        "No data"}
                      {odds && ` · ${Math.round((odds[i] ?? 0) * 100)}%`}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <h3>Alliance {selected + 1} report</h3>
        <Report teams={teams[selected] ?? []} robots={robots} />
      </section>
    </div>
  );
}
