import { type FormEvent, Fragment, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { useFormConfig, usePitEntries } from "../data/useCollections";
import { parseTeamNumber } from "../now/myTeam";
import { PickedMark } from "../picks/PickedMark";
import { TeamLink } from "../ui/TeamLink";
import { useWide } from "../ui/useWide";
import { CompareAi } from "./CompareAi";
import {
  buildMetrics,
  type Metric,
  type MetricCell,
  maxCompare,
  minCompare,
  newestPit,
  parseCompare,
} from "./compare";
import { DataNotices, Missing, Sparkline } from "./parts";
import { emptyRow, type TeamRow } from "./rows";
import { useTeamData } from "./useTeamData";

function CellValue({ cell }: { cell: MetricCell }) {
  if (cell.series) return <Sparkline series={cell.series} />;
  return (
    <>
      {cell.text ?? <Missing />}
      {cell.error && <span className="cmp-error">{cell.error}</span>}
      {cell.best && <span className="sr-only"> (best)</span>}
    </>
  );
}

function MetricTable({
  rows,
  groups,
}: {
  rows: TeamRow[];
  groups: ReturnType<typeof buildMetrics>;
}) {
  return (
    <div className="teams-scroll">
      <table className="teams-table cmp-table">
        <caption className="sr-only">Selected teams side by side</caption>
        <thead>
          <tr>
            <th scope="col" className="teams-left">
              Stat
            </th>
            {rows.map((r) => (
              <th key={r.team} scope="col" className="cmp-head">
                <TeamLink team={r.team} />
                {r.nickname !== "" && (
                  <span className="teams-nick">{r.nickname}</span>
                )}
                <PickedMark team={r.team} />
              </th>
            ))}
          </tr>
        </thead>
        {groups.map((group) => (
          <tbody key={group.id}>
            <tr className="cmp-group">
              <th scope="colgroup" colSpan={rows.length + 1}>
                {group.title}
              </th>
            </tr>
            {group.metrics.map((m: Metric) => (
              <Fragment key={m.id}>
                <tr>
                  <th scope="row" className="teams-left">
                    {m.label}
                  </th>
                  {m.cells.map((c) => (
                    <td key={c.team} data-best={c.best || undefined}>
                      <CellValue cell={c} />
                    </td>
                  ))}
                </tr>
                {m.note && (
                  <tr>
                    <td
                      colSpan={rows.length + 1}
                      className="cmp-note teams-left"
                    >
                      {m.note}
                    </td>
                  </tr>
                )}
              </Fragment>
            ))}
            {group.note && (
              <tr>
                <td colSpan={rows.length + 1} className="secondary teams-left">
                  {group.note}
                </td>
              </tr>
            )}
          </tbody>
        ))}
      </table>
    </div>
  );
}

function MetricStack({ groups }: { groups: ReturnType<typeof buildMetrics> }) {
  return (
    <>
      {groups.map((group) => (
        <section key={group.id} className="cmp-section">
          <h2>{group.title}</h2>
          {group.metrics.map((m) => (
            <div key={m.id} className="cmp-metric">
              <h3>{m.label}</h3>
              <ul className="teams-list">
                {m.cells.map((c) => (
                  <li
                    key={c.team}
                    className="cmp-line"
                    data-best={c.best || undefined}
                  >
                    <span className="cmp-team">{c.team}</span>
                    <span className="cmp-value">
                      <CellValue cell={c} />
                    </span>
                  </li>
                ))}
              </ul>
              {m.note && <p className="cmp-note">{m.note}</p>}
            </div>
          ))}
          {group.note && <p className="secondary">{group.note}</p>}
        </section>
      ))}
    </>
  );
}

export function Compare() {
  const [search, setSearch] = useSearchParams();
  const teams = parseCompare(search.get("t"));
  const data = useTeamData();
  const pit = usePitEntries();
  const pitConfig = useFormConfig("pit");
  const wide = useWide();
  const [typed, setTyped] = useState("");
  const [problem, setProblem] = useState<string | null>(null);

  const byTeam = useMemo(
    () => new Map(data.rows.map((r) => [r.team, r])),
    [data.rows],
  );
  const rows = teams.map((t) => byTeam.get(t) ?? emptyRow(t));
  const newest = useMemo(() => newestPit(pit.items), [pit.items]);
  const groups = useMemo(
    () =>
      buildMetrics(rows, newest, pitConfig).filter(
        (group) =>
          (group.id !== "pit" || (pit.ready && !pit.failed)) &&
          (group.id !== "scouted" || data.entries.ready),
      ),
    [rows, newest, pitConfig, pit.ready, pit.failed, data.entries.ready],
  );

  const setTeams = (next: number[]) =>
    setSearch(next.length === 0 ? {} : { t: next.join(",") }, {
      replace: true,
    });

  const add = (event: FormEvent) => {
    event.preventDefault();
    const team = parseTeamNumber(typed);
    if (team === null) return setProblem("Enter a team number, like 1111.");
    if (teams.includes(team))
      return setProblem(`Team ${team} is already here.`);
    if (teams.length >= maxCompare) {
      return setProblem(`Compare takes up to ${maxCompare} teams.`);
    }
    if (data.rows.length > 0 && !byTeam.has(team)) {
      return setProblem(`Team ${team} is not at this event.`);
    }
    setProblem(null);
    setTyped("");
    setTeams([...teams, team]);
  };

  const full = teams.length >= maxCompare;

  return (
    <div className="teams">
      <header className="teams-head">
        <h1>Compare teams</h1>
        <Link to="/teams">Back to teams</Link>
      </header>

      <DataNotices data={data} />

      <section className="cmp-picker" aria-label="Teams to compare">
        {teams.length > 0 && (
          <ul className="cmp-chips">
            {rows.map((r) => (
              <li key={r.team} className="cmp-chip">
                <span>
                  {r.team}
                  {r.nickname !== "" && ` ${r.nickname}`}
                </span>
                <button
                  type="button"
                  className="btn"
                  aria-label={`Remove ${r.team}`}
                  onClick={() => setTeams(teams.filter((t) => t !== r.team))}
                >
                  Remove
                </button>
              </li>
            ))}
          </ul>
        )}
        <form className="cmp-add" onSubmit={add}>
          <label className="teams-field">
            <span className="label">Add a team by number</span>
            <input
              className="input"
              inputMode="numeric"
              value={typed}
              disabled={full}
              onChange={(e) => setTyped(e.target.value)}
              autoComplete="off"
            />
          </label>
          <button type="submit" className="btn" disabled={full}>
            Add
          </button>
        </form>
        {problem && (
          <p className="notice" role="alert">
            {problem}
          </p>
        )}
        {full && (
          <p className="secondary">Compare takes up to {maxCompare} teams.</p>
        )}
      </section>

      {teams.length === 0 ? (
        <p className="secondary">
          Add {minCompare} to {maxCompare} teams above, or tick them in the{" "}
          <Link to="/teams">team list</Link>.
        </p>
      ) : (
        <>
          {teams.length < minCompare && (
            <p className="secondary">Add one more team to compare.</p>
          )}
          {rows.some((r) => !byTeam.has(r.team)) && data.rows.length > 0 && (
            <p className="notice-soft" role="status">
              {`Not at this event: ${rows
                .filter((r) => !byTeam.has(r.team))
                .map((r) => r.team)
                .join(", ")}.`}
            </p>
          )}
          {!pit.ready && !pit.failed && (
            <p className="secondary" role="status">
              Loading pit entries.
            </p>
          )}
          {pit.failed && (
            <p className="notice" role="status">
              Could not read pit entries. The comparison may be incomplete.
            </p>
          )}
          {wide ? (
            <MetricTable rows={rows} groups={groups} />
          ) : (
            <MetricStack groups={groups} />
          )}
          <CompareAi
            teams={teams}
            eventKey={data.eventKey}
            entries={data.entries.items}
          />
          <p className="secondary teams-legend">
            The best value in a row is bold and tinted when the teams differ.
            Scores are typical: they leave out matches with a breakdown and
            matches far from the team&apos;s own median, and ± is the standard
            error of that average. Teams whose scores differ by less than their
            ± together are too close to call. Pit answers come from each
            team&apos;s newest pit entry. The address of this page holds the
            teams, so it can be shared.
          </p>
        </>
      )}
    </div>
  );
}
