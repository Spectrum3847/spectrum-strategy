import { useMemo, useState } from "react";
import { useWide } from "../ui/useWide";
import { DbList } from "./DbList";
import { type BrowseProps, DbTable } from "./DbTable";
import { heldRows, holdIds } from "./hold";
import {
  defaultSort,
  type Filters,
  filterRows,
  noFilters,
  type Sort,
  type SortKey,
  scoutNames,
  sortKeys,
  sortRows,
} from "./rows";

export const pageSize = 100;

export function Browse({
  kind,
  rows: allRows,
  fields,
  onCorrect,
  onHistory,
  remover,
  editor,
}: BrowseProps) {
  const wide = useWide();
  const [held, setHeld] = useState<Set<string> | null>(null);
  const { shown: rows, waiting } = useMemo(
    () => heldRows(allRows, held),
    [allRows, held],
  );
  const [sort, setSort] = useState<Sort>(() => defaultSort(kind));
  const [filters, setFilters] = useState<Filters>(noFilters);
  const [limit, setLimit] = useState(pageSize);

  const sorted = useMemo(() => sortRows(rows, sort), [rows, sort]);
  const shown = useMemo(() => filterRows(sorted, filters), [sorted, filters]);
  const scouts = useMemo(() => scoutNames(rows), [rows]);
  const page = shown.slice(0, limit);
  const filtered = shown.length !== rows.length;
  const keys = sortKeys[kind];
  const descending = Object.fromEntries(
    keys.map((k) => [k.key, k.descending]),
  ) as Record<SortKey, boolean>;

  const change = (patch: Partial<Filters>) => {
    setFilters((f) => ({ ...f, ...patch }));
    setLimit(pageSize);
  };
  const order = (next: Sort) => {
    setSort(next);
    setLimit(pageSize);
  };
  const onSort = (key: SortKey) =>
    order({ key, reversed: sort.key === key && !sort.reversed });

  if (rows.length === 0) return null;

  return (
    <>
      {waiting > 0 && (
        <p className="notice-soft db-newdata" role="status">
          {`${waiting} new ${waiting === 1 ? "entry" : "entries"} arrived. `}
          <button
            type="button"
            className="btn"
            onClick={() => setHeld(holdIds(allRows))}
          >
            New data, refresh
          </button>
        </p>
      )}
      <div className="db-tools">
        <label className="db-field-box">
          <span className="label">Team</span>
          <input
            className="input"
            type="search"
            inputMode="numeric"
            value={filters.team}
            onChange={(e) => change({ team: e.target.value })}
            autoComplete="off"
          />
        </label>
        <label className="db-field-box">
          <span className="label">Scout</span>
          <select
            className="input"
            value={filters.scout}
            onChange={(e) => change({ scout: e.target.value })}
          >
            <option value="">All scouts</option>
            {scouts.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </label>
        {kind === "match" && (
          <>
            <label className="db-field-box db-num">
              <span className="label">From match</span>
              <input
                className="input"
                inputMode="numeric"
                value={filters.from}
                onChange={(e) => change({ from: e.target.value })}
                autoComplete="off"
              />
            </label>
            <label className="db-field-box db-num">
              <span className="label">To match</span>
              <input
                className="input"
                inputMode="numeric"
                value={filters.to}
                onChange={(e) => change({ to: e.target.value })}
                autoComplete="off"
              />
            </label>
          </>
        )}
        {!wide && (
          <div className="db-field-box">
            <label className="label" htmlFor="db-sort">
              Sort by
            </label>
            <div className="db-sortrow">
              <select
                id="db-sort"
                className="input"
                value={sort.key}
                onChange={(e) =>
                  order({ key: e.target.value as SortKey, reversed: false })
                }
              >
                {keys.map((k) => (
                  <option key={k.key} value={k.key}>
                    {k.label}
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="btn"
                aria-pressed={sort.reversed}
                onClick={() => order({ ...sort, reversed: !sort.reversed })}
              >
                Reverse
              </button>
            </div>
          </div>
        )}
      </div>
      {kind === "match" && (filters.from !== "" || filters.to !== "") && (
        <p className="secondary">
          The match range covers qualification matches.
        </p>
      )}

      {shown.length === 0 ? (
        <p className="secondary" role="status">
          No entry matches these filters.
        </p>
      ) : (
        <>
          <p className="secondary" role="status">
            {filtered
              ? `${shown.length} of ${rows.length} entries.`
              : `${rows.length} ${rows.length === 1 ? "entry" : "entries"}.`}
          </p>
          {wide ? (
            <DbTable
              kind={kind}
              rows={page}
              fields={fields}
              onCorrect={onCorrect}
              onHistory={onHistory}
              remover={remover}
              editor={editor}
              onEngage={
                editor && held === null
                  ? () => setHeld(holdIds(allRows))
                  : undefined
              }
              sort={sort}
              onSort={onSort}
              descending={descending}
            />
          ) : (
            <DbList
              kind={kind}
              rows={page}
              fields={fields}
              onCorrect={onCorrect}
              onHistory={onHistory}
              remover={remover}
            />
          )}
          {shown.length > page.length && (
            <div className="actions db-more">
              <button
                type="button"
                className="btn"
                onClick={() => setLimit((n) => n + pageSize)}
              >
                {`Show ${Math.min(pageSize, shown.length - page.length)} more`}
              </button>
              <span className="secondary">
                {`Showing ${page.length} of ${shown.length}.`}
              </span>
            </div>
          )}
        </>
      )}
    </>
  );
}
