import { useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { usePitEntries } from "../data/useCollections";
import { useWide } from "../ui/useWide";
import { compareHref, maxCompare, minCompare, newestPit } from "./compare";
import {
  evaluateFilters,
  type FilterId,
  filterDefs,
  filterIds,
  filtersParam,
  parseFilters,
  passes,
} from "./filters";
import { heatMap } from "./heat";
import { compareLimitNote, DataNotices } from "./parts";
import {
  defaultPlaces,
  defaultSort,
  orderNotice,
  type Sort,
  type SortKey,
  searchRows,
  sortKeyOrder,
  sortKeys,
  sortRows,
} from "./sort";
import { TeamFilterBar } from "./TeamFilterBar";
import { TeamList } from "./TeamList";
import { TeamTable } from "./TeamTable";
import { useTeamData } from "./useTeamData";

export function Teams() {
  const data = useTeamData();
  const { eventKey, tba, epa, taken, rows } = data;
  const pit = usePitEntries();
  const [params, setParams] = useSearchParams();
  const wide = useWide();
  const [sort, setSort] = useState<Sort>(defaultSort);
  const [query, setQuery] = useState("");
  const [chosen, setChosen] = useState<number[]>([]);

  const places = useMemo(() => defaultPlaces(rows), [rows]);
  const heat = useMemo(() => heatMap(rows), [rows]);
  const sorted = useMemo(() => sortRows(rows, sort), [rows, sort]);
  const showPit = pit.ready && !pit.failed;
  const results = useMemo(
    () =>
      evaluateFilters({
        config: data.config,
        teams: rows.map((r) => r.team),
        entries: data.entries.items,
        pit: newestPit(pit.items),
      }),
    [data.config, rows, data.entries.items, pit.items],
  );
  const active = parseFilters(params.get("f")).filter(
    (id) => showPit || !filterDefs.find((d) => d.id === id)?.needsPit,
  );
  const setActive = (next: FilterId[]) =>
    setParams(
      (p) => {
        const out = new URLSearchParams(p);
        if (next.length === 0) out.delete("f");
        else out.set("f", filtersParam(next));
        return out;
      },
      { replace: true },
    );
  const onFilter = (id: FilterId) =>
    setActive(
      filterIds.filter((f) =>
        f === id ? !active.includes(id) : active.includes(f),
      ),
    );
  const filtered = useMemo(
    () => sorted.filter((r) => passes(results, r.team, active)),
    [sorted, results, active],
  );
  const shown = useMemo(() => searchRows(filtered, query), [filtered, query]);
  const notice = orderNotice(rows, epa.status);
  const scouted = rows.filter((r) => r.matches > 0).length;

  const onSort = (key: SortKey) =>
    setSort((s) => ({ key, reversed: s.key === key && !s.reversed }));
  const onToggle = (team: number) =>
    setChosen((c) =>
      c.includes(team)
        ? c.filter((t) => t !== team)
        : c.length < maxCompare
          ? [...c, team]
          : c,
    );

  return (
    <div className="teams">
      <header className="teams-head">
        <h1>Teams</h1>
        <Link className="btn" to="/teams/analysis">
          Event analysis
        </Link>
        {eventKey !== "" && (
          <p className="secondary">
            {`${eventKey}: ${rows.length} ${rows.length === 1 ? "team" : "teams"}, ${data.entries.ready ? `${scouted} scouted` : "loading scouted stats"}`}
          </p>
        )}
      </header>

      <DataNotices data={data} />
      {notice && (
        <p className="notice-soft" role="status">
          {notice}
        </p>
      )}

      {!data.entries.ready && eventKey !== "" ? null : rows.length === 0 ? (
        eventKey !== "" && (
          <p className="secondary" role="status">
            {tba.status === "loading" || tba.status === "none"
              ? "Loading the team list."
              : `No teams yet for ${eventKey}. The team list comes from The Blue Alliance.`}
          </p>
        )
      ) : (
        <>
          <div className="teams-tools">
            <label className="teams-field">
              <span className="label">Search by number or nickname</span>
              <input
                className="input"
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                autoComplete="off"
              />
            </label>
            {!wide && (
              <div className="teams-field">
                <label className="label" htmlFor="teams-sort">
                  Sort by
                </label>
                <div className="teams-sortrow">
                  <select
                    id="teams-sort"
                    className="input"
                    value={sort.key}
                    onChange={(e) =>
                      setSort({
                        key: e.target.value as SortKey,
                        reversed: false,
                      })
                    }
                  >
                    {sortKeyOrder.map((key) => (
                      <option key={key} value={key}>
                        {key === "epa"
                          ? "EPA, else TBA rank"
                          : sortKeys[key].label}
                      </option>
                    ))}
                  </select>
                  <button
                    type="button"
                    className="btn"
                    aria-pressed={sort.reversed}
                    onClick={() =>
                      setSort((s) => ({ ...s, reversed: !s.reversed }))
                    }
                  >
                    Reverse
                  </button>
                </div>
              </div>
            )}
          </div>

          <div className="teams-compare">
            <p className="secondary" role="status">
              {chosen.length === 0
                ? `Tick ${minCompare} to ${maxCompare} teams to compare them.`
                : chosen.length >= maxCompare
                  ? `${chosen.length} ticked. ${compareLimitNote}`
                  : `${chosen.length} ticked.`}
            </p>
            {chosen.length >= minCompare ? (
              <Link className="btn primary" to={compareHref(chosen)}>
                Compare
              </Link>
            ) : (
              <button type="button" className="btn" disabled>
                Compare
              </button>
            )}
            {chosen.length > 0 && (
              <button
                type="button"
                className="btn"
                onClick={() => setChosen([])}
              >
                Clear ticks
              </button>
            )}
          </div>

          <TeamFilterBar
            results={results}
            active={active}
            shown={filtered.length}
            showPit={showPit}
            onToggle={onFilter}
            onClear={() => setActive([])}
          />

          {query.trim() !== "" && (
            <p className="secondary" role="status">
              {`${shown.length} of ${filtered.length} teams.`}
            </p>
          )}

          {shown.length === 0 ? (
            query.trim() !== "" && (
              <p className="secondary" role="status">
                {`No team matches "${query.trim()}".`}
              </p>
            )
          ) : wide ? (
            <TeamTable
              rows={shown}
              places={places}
              heat={heat}
              sort={sort}
              onSort={onSort}
              taken={taken}
              chosen={chosen}
              onToggle={onToggle}
            />
          ) : (
            <TeamList
              rows={shown}
              places={places}
              taken={taken}
              chosen={chosen}
              onToggle={onToggle}
            />
          )}

          {wide && shown.length > 0 && (
            <p className="secondary teams-legend">
              Score is the typical match total: the average without breakdown
              matches (died, disconnected or no show) and without matches far
              from the team&apos;s own median. Floor is a bad day, the 25th
              percentile of those matches, from 4 matches. SD is the spread,
              lower is steadier, from 3 matches. Works is matches without a
              breakdown. Form is the last 3 match totals against the ones
              before, from 5 matches. It predicted worst in a backtest on 2026
              event data, so use it to spot a change, not to rank. n is matches
              scouted. A darker, bolder cell is higher in its column (lower for
              SD). A greyed team has been picked in the draft.
            </p>
          )}
        </>
      )}
    </div>
  );
}
