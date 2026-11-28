import { useState } from "react";
import { readCache, writeCache } from "../data/cache";
import { matchLabel } from "../data/matchKey";
import { Cite } from "./Cite";
import type { CountRow } from "./counts";
import { formatStat, percent } from "./format";
import type { LeftOutReason } from "./spread";
import type { RateRow, StatRow, TeamStats } from "./stats";

type View = "table" | "tiles";
const viewKey = "ss.team.statsView";

function useView(): [View, (next: View) => void] {
  const [view, setView] = useState<View>(() =>
    readCache<string>(viewKey) === "tiles" ? "tiles" : "table",
  );
  return [
    view,
    (next) => {
      setView(next);
      writeCache(viewKey, next);
    },
  ];
}

function bySection(rows: StatRow[]): [string, StatRow[]][] {
  const groups = new Map<string, StatRow[]>();
  for (const row of rows) {
    groups.set(row.section, [...(groups.get(row.section) ?? []), row]);
  }
  return [...groups];
}

const cell = (n: number | null) => (n === null ? "-" : formatStat(n));

const range = (row: StatRow) =>
  row.range === null
    ? null
    : `${formatStat(row.range[0])} to ${formatStat(row.range[1])}`;

function Typical({ row }: { row: StatRow }) {
  return (
    <>
      {formatStat(row.typical)}
      {row.se !== null && (
        <span className="team-error">{`±${formatStat(row.se)}`}</span>
      )}
    </>
  );
}

const withSign = (n: number) => (n > 0 ? `+${formatStat(n)}` : formatStat(n));

const matchWord = (n: number) => (n === 1 ? "match" : "matches");

function Reliability({ stats }: { stats: TeamStats }) {
  const { ok, of } = stats.reliability;
  const trend = stats.trend;
  if (of === 0) return null;
  return (
    <div className="team-reliability">
      <p>{`${ok} of ${of} ${matchWord(of)} without a breakdown`}</p>
      {trend && trend.direction !== "steady" && (
        <span
          className="team-tag"
          title={`Later matches average ${formatStat(trend.later)} against ${formatStat(trend.earlier)} earlier, more than normal match to match swings.`}
        >
          {`${trend.direction === "improving" ? "Improving" : "Declining"} ${withSign(trend.delta)}`}
        </span>
      )}
    </div>
  );
}

const reasonText: Record<LeftOutReason, string> = {
  breakdown: "breakdown",
  low: "far below usual",
  high: "far above usual",
};

function LeftOut({ total }: { total: StatRow | null }) {
  if (!total) return null;
  if (total.leftOut.length === 0) {
    return <p className="secondary">Typical counts every match.</p>;
  }
  return (
    <div className="team-leftout">
      <p className="secondary">Typical leaves out:</p>
      <ul className="team-leftout-list">
        {total.leftOut.map((m) => (
          <li key={m.key}>
            <Cite cite={{ key: m.key, label: matchLabel(m.key) }} />
            <span className="secondary">
              {`${formatStat(m.value)}, ${reasonText[m.reason]}`}
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function StatsTable({
  stats,
  caption,
}: {
  stats: TeamStats;
  caption: string;
}) {
  const groups: [string, StatRow[]][] = [
    ...(stats.total ? ([["", [stats.total]]] as [string, StatRow[]][]) : []),
    ...bySection(stats.rows),
  ];
  return (
    <>
      {groups.length > 0 && (
        <div className="team-scroll">
          <table className="team-table">
            <caption className="sr-only">{caption}</caption>
            <thead>
              <tr>
                <th scope="col">Stat</th>
                <th scope="col">Typical</th>
                <th scope="col">Usual range</th>
                <th scope="col">Best</th>
                <th scope="col">IQM</th>
                <th scope="col">n</th>
              </tr>
            </thead>
            {groups.map(([section, rows]) => (
              <tbody key={section}>
                {section !== "" && (
                  <tr className="team-table-section">
                    <th scope="colgroup" colSpan={6}>
                      {section}
                    </th>
                  </tr>
                )}
                {rows.map((row) => (
                  <tr key={row.code}>
                    <th scope="row">{row.label}</th>
                    <td>
                      <Typical row={row} />
                    </td>
                    <td>{range(row) ?? "-"}</td>
                    <td>{cell(row.max)}</td>
                    <td>{cell(row.iqm)}</td>
                    <td>{row.n}</td>
                  </tr>
                ))}
              </tbody>
            ))}
          </table>
        </div>
      )}
      {stats.rates.length > 0 && (
        <div className="team-scroll">
          <table className="team-table">
            <caption className="sr-only">{`${caption}, rates`}</caption>
            <thead>
              <tr>
                <th scope="col">Rate</th>
                <th scope="col">Matches</th>
                <th scope="col">Share</th>
              </tr>
            </thead>
            <tbody>
              {stats.rates.map((rate) => (
                <tr key={rate.code}>
                  <th scope="row">{rate.label}</th>
                  <td>{`${rate.successes} / ${rate.total}`}</td>
                  <td>{percent(rate.successes, rate.total)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}

function StatTile({ row }: { row: StatRow }) {
  return (
    <li className="team-tile">
      <span className="team-tile-label">{row.label}</span>
      <span className="team-tile-value">
        <Typical row={row} />
      </span>
      <span className="team-tile-note">
        {[
          range(row) === null ? "" : `Usual ${range(row)}`,
          `Best ${formatStat(row.max)}`,
          `IQM ${formatStat(row.iqm)}`,
          `n ${row.n}`,
        ]
          .filter((part) => part !== "")
          .join(", ")}
      </span>
    </li>
  );
}

function RateTile({ rate }: { rate: RateRow }) {
  return (
    <li className="team-tile">
      <span className="team-tile-label">{rate.label}</span>
      <span className="team-tile-value">{`${rate.successes} / ${rate.total}`}</span>
      <span className="team-tile-note">
        {`${percent(rate.successes, rate.total)} of matches`}
      </span>
    </li>
  );
}

export function StatsTiles({ stats }: { stats: TeamStats }) {
  const rows = [...(stats.total ? [stats.total] : []), ...stats.rows];
  return (
    <ul className="team-tiles">
      {rows.map((row) => (
        <StatTile key={row.code} row={row} />
      ))}
      {stats.rates.map((rate) => (
        <RateTile key={rate.code} rate={rate} />
      ))}
    </ul>
  );
}

export function ValueCounts({ rows }: { rows: CountRow[] }) {
  return (
    <dl className="team-counts">
      {rows.map((row) => (
        <div key={row.code} className="team-count">
          <dt>{row.label}</dt>
          <dd>{row.counts.map((c) => `${c.label} ${c.count}`).join(", ")}</dd>
        </div>
      ))}
    </dl>
  );
}

export function StatsSection({
  team,
  stats,
  counts,
}: {
  team: number;
  stats: TeamStats;
  counts: CountRow[];
}) {
  const [view, setView] = useView();
  const empty =
    stats.rows.length === 0 &&
    stats.rates.length === 0 &&
    !stats.total &&
    counts.length === 0;
  return (
    <section className="team-section" aria-labelledby="team-stats">
      <div className="team-section-head">
        <h2 id="team-stats">Event stats</h2>
        {!empty && (
          <fieldset className="chips team-toggle">
            <legend className="sr-only">Stats view</legend>
            {(["table", "tiles"] as const).map((v) => (
              <button
                key={v}
                type="button"
                className="chip"
                aria-pressed={view === v}
                onClick={() => setView(v)}
              >
                {v === "table" ? "Table" : "Tiles"}
              </button>
            ))}
          </fieldset>
        )}
      </div>
      {empty ? (
        <p className="secondary">No scouting entries for this team yet.</p>
      ) : (
        <>
          <p className="secondary">
            {`${stats.matches} ${stats.matches === 1 ? "match" : "matches"} scouted. A match with several scouts counts once.`}
          </p>
          <Reliability stats={stats} />
          <LeftOut total={stats.total} />
          {view === "table" ? (
            <StatsTable stats={stats} caption={`Team ${team} scouted stats`} />
          ) : (
            <StatsTiles stats={stats} />
          )}
          {counts.length > 0 && <ValueCounts rows={counts} />}
          <p className="secondary">
            Typical is the average after leaving out matches with a breakdown
            (died, disconnected or no show) and matches far from the team&apos;s
            own median (more than 2.5 MAD, from 5 matches). ± is its standard
            error: teams closer than that are too close to call. Usual range is
            the 25th to 75th percentile of the same matches, from 4 matches, and
            its low end is a bad day. Best and IQM use every match. IQM is the
            mean of the middle half.
            {stats.total &&
              " Match total adds the counters in the auto, teleop and endgame sections."}
          </p>
        </>
      )}
    </section>
  );
}
