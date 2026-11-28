import { Link } from "react-router";
import { historyList } from "../corrections/history";
import { matchPath } from "../data/matchKey";
import type { ScoutField } from "../scout/config";
import { when } from "../team/Sections";
import { DeleteButton } from "../ui/DeleteButton";
import { TeamLink } from "../ui/TeamLink";
import { DbCell } from "./DbCell";
import { flagLabel } from "./flags";
import type { DbRow, Kind, Sort, SortKey } from "./rows";
import type { CellEditor } from "./useCellEditor";
import { useGrid } from "./useGrid";

export interface BrowseProps {
  kind: Kind;
  rows: DbRow[];
  fields: ScoutField[];
  onCorrect?: ((id: string) => void) | undefined;
  remover?: Remover | undefined;
  editor?: CellEditor | undefined;
  onHistory?: ((id: string) => void) | undefined;
  onEngage?: (() => void) | undefined;
}

export const historyCount = (row: DbRow) =>
  historyList(
    row.entry?.correction ?? null,
    row.corrected,
    row.rawValues,
    row.values,
  ).length;

export function RowActions({
  row,
  onCorrect,
  onHistory,
  remover,
}: Pick<BrowseProps, "onCorrect" | "onHistory" | "remover"> & { row: DbRow }) {
  const label = `team ${row.team}, ${row.label}`;
  return (
    <>
      {onHistory && (
        <button
          type="button"
          className="btn db-action"
          aria-label={`History for ${label}`}
          onClick={() => onHistory(row.id)}
        >
          {`History (${historyCount(row)})`}
        </button>
      )}
      {onCorrect && (
        <button
          type="button"
          className="btn db-action"
          aria-label={`Form for ${label}`}
          onClick={() => onCorrect(row.id)}
        >
          Form
        </button>
      )}
      {remover && <DeleteRow row={row} remover={remover} />}
    </>
  );
}

export interface Remover {
  can(row: DbRow): boolean;
  run(row: DbRow): Promise<void>;
}

export function DeleteRow({ row, remover }: { row: DbRow; remover: Remover }) {
  if (!remover.can(row)) return null;
  const what = row.team > 0 ? `team ${row.team}` : "entry";
  return (
    <DeleteButton
      what={`${what}${row.label ? `, ${row.label}` : ""}`}
      prompt={`Delete this entry for ${what}?`}
      onConfirm={() => remover.run(row)}
    />
  );
}

interface TableProps extends BrowseProps {
  sort: Sort;
  onSort: (key: SortKey) => void;
  descending: Record<SortKey, boolean>;
}

function Chevron({ up }: { up: boolean }) {
  return (
    <svg
      className="db-chevron"
      viewBox="0 0 24 24"
      width="16"
      height="16"
      aria-hidden="true"
      focusable="false"
      style={{ transform: up ? "rotate(180deg)" : undefined }}
    >
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

function SortHead({
  sortKey,
  label,
  sort,
  descending,
  onSort,
  className,
}: {
  sortKey: SortKey;
  label: string;
  sort: Sort;
  descending: boolean;
  onSort: (key: SortKey) => void;
  className?: string;
}) {
  const active = sort.key === sortKey;
  const down = descending !== sort.reversed;
  return (
    <th
      scope="col"
      {...(className ? { className } : {})}
      aria-sort={active ? (down ? "descending" : "ascending") : undefined}
    >
      <button
        type="button"
        className="db-sortbtn"
        data-active={active || undefined}
        onClick={() => onSort(sortKey)}
      >
        {label}
        {active && <Chevron up={!down} />}
      </button>
    </th>
  );
}

export function MatchLink({ row }: { row: DbRow }) {
  return row.href ? (
    <Link className="db-link" to={matchPath(row.href)}>
      {row.label}
    </Link>
  ) : (
    <span>{row.label}</span>
  );
}

export function Station({ station }: { station: string }) {
  if (station === "") return null;
  return (
    <span
      className="tag"
      data-alliance={station.startsWith("R") ? "red" : "blue"}
    >
      <span className="sr-only">Station </span>
      {station}
    </span>
  );
}

export function FlagBadge({ row }: { row: DbRow }) {
  const worst = row.flags[0];
  if (!worst) return null;
  return (
    <span className="db-flag" data-flag={worst.kind}>
      {flagLabel[worst.kind]}
      <span className="sr-only">{`: ${row.flags.map((f) => f.reason).join(" ")}`}</span>
    </span>
  );
}

export function DbTable({
  kind,
  rows,
  fields,
  onCorrect,
  remover,
  editor,
  onHistory,
  onEngage,
  sort,
  onSort,
  descending,
}: TableProps) {
  const grid = useGrid(rows, fields, editor, onEngage);
  const actions = onCorrect || onHistory || remover;
  const head = (key: SortKey, label: string, className?: string) => (
    <SortHead
      sortKey={key}
      label={label}
      sort={sort}
      descending={descending[key]}
      onSort={onSort}
      {...(className ? { className } : {})}
    />
  );
  const flagged = rows.some((r) => r.flags.length > 0);
  const incidents = rows.some((r) => r.incidents !== "");
  return (
    <div className="db-scroll">
      <table
        ref={grid.table}
        className="db-table"
        {...(editor ? { role: "grid" } : {})}
      >
        <caption className="sr-only">
          {editor
            ? "Entries. Press a column heading to sort. Arrow keys move between answers, Enter edits, Escape cancels."
            : "Entries. Press a column heading to sort."}
        </caption>
        <thead>
          <tr>
            {actions && (
              <th scope="col" className="db-left db-actions-col">
                Actions
              </th>
            )}
            {head("team", "Team", "db-left db-team-col")}
            {kind === "match" ? (
              <>
                {head("match", "Match", "db-left")}
                <th scope="col" className="db-left">
                  Station
                </th>
                {head("scout", "Scout", "db-left")}
              </>
            ) : (
              <>
                <th scope="col" className="db-left">
                  Event
                </th>
                {head("scout", "Scout", "db-left")}
                {head("updated", "Updated", "db-left")}
              </>
            )}
            {flagged && (
              <th scope="col" className="db-left">
                Check
              </th>
            )}
            {incidents && (
              <th scope="col" className="db-left">
                Cards and deaths
              </th>
            )}
            {fields.map((f) => (
              <th key={f.code} scope="col" className="db-field">
                {f.title.trim() || f.code}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, r) => (
            <tr key={row.id} data-flag={row.flags[0]?.kind}>
              {actions && (
                <td className="db-left db-actions-col">
                  <div className="db-rowactions">
                    <RowActions
                      row={row}
                      onCorrect={onCorrect}
                      onHistory={onHistory}
                      remover={remover}
                    />
                  </div>
                </td>
              )}
              <th scope="row" className="db-team db-team-col">
                {row.team > 0 ? <TeamLink team={row.team} /> : "?"}
              </th>
              {kind === "match" ? (
                <>
                  <td className="db-left">
                    <MatchLink row={row} />
                  </td>
                  <td className="db-left">
                    <Station station={row.station} />
                  </td>
                  <td className="db-left">{row.scout}</td>
                </>
              ) : (
                <>
                  <td className="db-left">{row.event}</td>
                  <td className="db-left">{row.scout}</td>
                  <td className="db-left">{when(row.updatedAt)}</td>
                </>
              )}
              {flagged && (
                <td
                  className="db-left"
                  title={row.flags.map((f) => f.reason).join("\n")}
                >
                  <FlagBadge row={row} />
                </td>
              )}
              {incidents && (
                <td className="db-left db-incident">{row.incidents}</td>
              )}
              {fields.map((f, c) => (
                <DbCell
                  key={f.code}
                  field={f}
                  row={row}
                  grid={grid}
                  r={r}
                  c={c}
                />
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
