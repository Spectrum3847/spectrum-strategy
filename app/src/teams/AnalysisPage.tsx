import { useMemo, useState } from "react";
import { Link } from "react-router";
import { useMyTeam } from "../now/myTeam";
import { allFields } from "../scout/config";
import { formatStat } from "../team/format";
import { entryMatchKey, groupByMatch, mean, outcomes } from "../team/stats";
import { TeamLink } from "../ui/TeamLink";
import { DataNotices } from "./parts";
import type { TeamRow } from "./rows";
import { useTeamData } from "./useTeamData";
import "./analysis.css";

export function quantile(sorted: number[], p: number): number {
  const i = (sorted.length - 1) * p;
  const low = Math.floor(i);
  return (
    (sorted[low] ?? 0) +
    ((sorted[Math.ceil(i)] ?? 0) - (sorted[low] ?? 0)) * (i - low)
  );
}

function Scatter({
  rows,
  x,
  y,
  label,
}: {
  rows: TeamRow[];
  x: (r: TeamRow) => number;
  y: (r: TeamRow) => number;
  label: string;
}) {
  const xmax = Math.max(1, ...rows.map(x));
  const ymax = Math.max(1, ...rows.map(y));
  return (
    <svg
      className="analysis-scatter"
      viewBox="0 0 400 240"
      role="img"
      aria-label={label}
    >
      <line x1="30" x2="390" y1="210" y2="210" stroke="currentColor" />
      <line x1="30" x2="30" y1="10" y2="210" stroke="currentColor" />
      {rows.map((r) => (
        <g key={r.team}>
          <circle
            cx={30 + (x(r) / xmax) * 350}
            cy={210 - (y(r) / ymax) * 190}
            r="4"
            fill="var(--accent)"
          >
            <title>
              {r.team}: {formatStat(x(r))}, {formatStat(y(r))}
            </title>
          </circle>
          <text
            x={35 + (x(r) / xmax) * 350}
            y={207 - (y(r) / ymax) * 190}
            fontSize="9"
            fill="currentColor"
          >
            {r.team}
          </text>
        </g>
      ))}
    </svg>
  );
}

export function Analysis() {
  const data = useTeamData();
  const us = useMyTeam();
  const [count, setCount] = useState(24);
  const rows = data.rows.filter((r) => r.iqm.total !== null);
  const ranked = [...rows].sort(
    (a, b) => (b.iqm.total ?? 0) - (a.iqm.total ?? 0) || a.team - b.team,
  );
  const climbers = useMemo(() => {
    const fields = allFields(data.config).filter((f) =>
      ["eLow", "eMiddle", "eHigh"].includes(f.code),
    );
    return data.rows
      .map((r) => {
        const inputs = data.entries.items
          .filter((e) => e.teamNumber === r.team)
          .map((e) => ({
            id: e.id,
            matchKey: entryMatchKey(e),
            fieldValues: e.fieldValues,
          }));
        const groups = groupByMatch(inputs);
        const byField = fields.map((f) => ({
          code: f.code,
          results: outcomes(f, groups) ?? [],
        }));
        let attempts = 0;
        let made = 0;
        let high = 0;
        for (const group of groups) {
          const results = byField.map((f) => ({
            code: f.code,
            outcome: f.results.find((o) => o.key === group.key)?.outcome,
          }));
          if (
            results.some(
              (v) => v.outcome === "positive" || v.outcome === "failed",
            )
          )
            attempts++;
          if (results.some((v) => v.outcome === "positive")) made++;
          if (
            results.some((v) => v.code === "eHigh" && v.outcome === "positive")
          )
            high++;
        }
        return { team: r.team, attempts, made, high };
      })
      .filter((r) => r.attempts >= 3)
      .sort(
        (a, b) =>
          b.high / b.attempts - a.high / a.attempts ||
          b.made / b.attempts - a.made / a.attempts ||
          a.team - b.team,
      );
  }, [data.config, data.entries.items, data.rows]);
  const movers = rows
    .filter((r) => r.series.length >= 5)
    .map((r) => ({
      team: r.team,
      before: mean(r.series.slice(0, -3).map((p) => p.value)),
      recent: mean(r.series.slice(-3).map((p) => p.value)),
    }))
    .sort(
      (a, b) => b.recent - b.before - (a.recent - a.before) || a.team - b.team,
    );
  return (
    <div className="teams analysis">
      <header className="teams-head">
        <h1>Event analysis</h1>
        <Link to="/teams">Back to teams</Link>
      </header>
      <DataNotices data={data} />
      {rows.length < 3 ? (
        <p>Analysis needs scouting data for at least 3 teams.</p>
      ) : (
        <>
          <section>
            <h2>Auto vs teleop</h2>
            <p className="secondary">
              Scouted IQM points. Auto is horizontal, teleop vertical.
            </p>
            <Scatter
              rows={rows}
              x={(r) => r.iqm.auto ?? 0}
              y={(r) => r.iqm.teleop ?? 0}
              label="Auto versus teleop IQM points"
            />
          </section>
          <section>
            <h2>Scoring vs consistency</h2>
            <p className="secondary">
              Mean points horizontally, standard deviation vertically. At least
              3 matches.
            </p>
            <Scatter
              rows={rows.filter((r) => r.sd !== null)}
              x={(r) => mean(r.series.map((p) => p.value))}
              y={(r) => r.sd ?? 0}
              label="Mean points versus standard deviation"
            />
          </section>
          <section>
            <h2>Match score spread</h2>
            <label>
              Teams shown{" "}
              <select
                className="input"
                value={count}
                onChange={(e) => setCount(Number(e.target.value))}
              >
                {[16, 24, 32].map((n) => (
                  <option key={n}>{n}</option>
                ))}
              </select>
            </label>
            <ul className="plain analysis-rows">
              {ranked.slice(0, count).map((r) => {
                const values = r.series
                  .map((p) => p.value)
                  .sort((a, b) => a - b);
                const max = Math.max(
                  1,
                  ...ranked.flatMap((team) => team.series.map((p) => p.value)),
                );
                return (
                  <li key={r.team}>
                    <TeamLink team={r.team} />
                    <svg
                      viewBox="0 0 300 28"
                      role="img"
                      aria-label={`Team ${r.team} match scores: ${values.map(formatStat).join(", ")}`}
                    >
                      <line
                        x1={((values[0] ?? 0) / max) * 290}
                        x2={((values[values.length - 1] ?? 0) / max) * 290}
                        y1="14"
                        y2="14"
                        stroke="currentColor"
                      />
                      <rect
                        x={(quantile(values, 0.25) / max) * 290}
                        y="8"
                        width={Math.max(
                          1,
                          ((quantile(values, 0.75) - quantile(values, 0.25)) /
                            max) *
                            290,
                        )}
                        height="12"
                        fill="var(--surface-2)"
                        stroke="currentColor"
                      />
                      <line
                        x1={(quantile(values, 0.5) / max) * 290}
                        x2={(quantile(values, 0.5) / max) * 290}
                        y1="8"
                        y2="20"
                        stroke="currentColor"
                      />
                      {r.series.map((point) => (
                        <circle
                          key={point.key}
                          cx={(point.value / max) * 290}
                          cy="14"
                          r="3"
                          fill="var(--accent)"
                        />
                      ))}
                    </svg>
                    <span>
                      {formatStat(values[0] ?? 0)} /{" "}
                      {formatStat(quantile(values, 0.5))} /{" "}
                      {formatStat(values[values.length - 1] ?? 0)}
                    </span>
                  </li>
                );
              })}
            </ul>
            <p className="secondary">
              Worst / median / best points. Each dot is one match.
            </p>
          </section>
          <section>
            <h2>IQM auto + teleop</h2>
            <ul className="plain analysis-rows">
              {[...rows]
                .sort(
                  (a, b) =>
                    (b.iqm.auto ?? 0) +
                      (b.iqm.teleop ?? 0) -
                      (a.iqm.auto ?? 0) -
                      (a.iqm.teleop ?? 0) || a.team - b.team,
                )
                .map((r) => {
                  const max = Math.max(
                    1,
                    ...rows.map((v) => (v.iqm.auto ?? 0) + (v.iqm.teleop ?? 0)),
                  );
                  return (
                    <li key={r.team} data-us={r.team === us || undefined}>
                      <TeamLink team={r.team} />
                      <svg
                        viewBox="0 0 300 20"
                        role="img"
                        aria-label={`Auto ${formatStat(r.iqm.auto ?? 0)}, teleop ${formatStat(r.iqm.teleop ?? 0)} points`}
                      >
                        <rect
                          width={((r.iqm.auto ?? 0) / max) * 290}
                          height="20"
                          fill="var(--phase-auto)"
                        />
                        <rect
                          x={((r.iqm.auto ?? 0) / max) * 290}
                          width={((r.iqm.teleop ?? 0) / max) * 290}
                          height="20"
                          fill="var(--phase-teleop)"
                        />
                      </svg>
                      <span>
                        {formatStat((r.iqm.auto ?? 0) + (r.iqm.teleop ?? 0))}{" "}
                        pts
                      </span>
                    </li>
                  );
                })}
            </ul>
          </section>
          <section>
            <h2>Biggest movers</h2>
            <p className="secondary">
              Mean scouted total points: earlier matches compared with the last
              3. At least 5 matches.
            </p>
            <ul>
              {movers.map((m) => (
                <li key={m.team}>
                  <TeamLink team={m.team} />: {formatStat(m.before)} to{" "}
                  {formatStat(m.recent)} pts (
                  {m.recent - m.before > 0 ? "+" : ""}
                  {formatStat(m.recent - m.before)} pts)
                </li>
              ))}
            </ul>
            {movers.length === 0 && <p>Not enough matches yet.</p>}
          </section>
          <section>
            <h2>Most reliable climbers</h2>
            <p className="secondary">
              At least 3 attempts, sorted by L3 success rate.
            </p>
            <ul>
              {climbers.map((c) => (
                <li key={c.team}>
                  <TeamLink team={c.team} />: {c.high} L3 and {c.made} total
                  successes in {c.attempts} attempts
                </li>
              ))}
            </ul>
            {climbers.length === 0 && <p>Not enough climb attempts yet.</p>}
          </section>
        </>
      )}
    </div>
  );
}
