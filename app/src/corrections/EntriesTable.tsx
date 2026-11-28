import { useMemo } from "react";
import { Link } from "react-router";
import { matchPath } from "../data/matchKey";
import type { EventEntry } from "../data/parse";
import { cellOf, type DbRow, matchRows, sortRows } from "../database/rows";
import type { ScoutConfig, ScoutField } from "../scout/config";
import { when } from "../team/Sections";
import type { Corrected } from "./apply";
import { EditNote } from "./EditNote";
import { entryColumns } from "./fields";

const title = (f: ScoutField) => f.title.trim() || f.code;

function Answer({
  field,
  row,
  comment,
}: {
  field: ScoutField;
  row: DbRow;
  comment?: boolean;
}) {
  const cell = cellOf(field, row);
  return (
    <td
      {...(comment ? { className: "entries-comment" } : {})}
      data-corrected={cell.was !== null || undefined}
    >
      {cell.text}
      {cell.was !== null && (
        <span className="entries-was">{`Scout entered ${cell.was}`}</span>
      )}
      {cell.edit && <EditNote edit={cell.edit} className="entries-was" />}
    </td>
  );
}

function Correction({ row }: { row: DbRow }) {
  const c = row.corrected.length > 0 ? row.entry?.correction : null;
  if (!c) return <td />;
  const by = [
    c.authorDisplayName,
    c.updatedMs > 0 ? when(new Date(c.updatedMs).toISOString()) : "",
  ]
    .filter((p) => p !== "")
    .join(", ");
  return (
    <td className="entries-comment">
      {by !== "" && <span className="entries-was">{by}</span>}
      {c.note}
    </td>
  );
}

export function EntriesTable({
  entries,
  config,
  onCorrect,
}: {
  entries: Corrected<EventEntry>[];
  config: ScoutConfig;
  onCorrect?: ((id: string) => void) | undefined;
}) {
  const { comments, answers } = useMemo(() => entryColumns(config), [config]);
  const rows = useMemo(
    () => sortRows(matchRows(entries), { key: "match", reversed: false }),
    [entries],
  );
  const incidents = rows.some((r) => r.incidents !== "");
  const corrected = rows.some((r) => r.corrected.length > 0);
  return (
    <div className="entries-scroll">
      <table className="entries-table">
        <caption className="sr-only">
          Every scout entry for this team, first match first.
        </caption>
        <thead>
          <tr>
            <th scope="col" className="entries-match">
              Match
            </th>
            {incidents && <th scope="col">Cards and deaths</th>}
            {comments.map((f) => (
              <th key={f.code} scope="col">
                {title(f)}
              </th>
            ))}
            {answers.map((f) => (
              <th key={f.code} scope="col">
                {title(f)}
              </th>
            ))}
            {corrected && <th scope="col">Correction</th>}
            <th scope="col">Scout</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <th scope="row" className="entries-match">
                <div className="entries-matchcell">
                  {row.href ? (
                    <Link className="entries-link" to={matchPath(row.href)}>
                      {row.label}
                    </Link>
                  ) : (
                    <span>{row.label}</span>
                  )}
                  {onCorrect && (
                    <button
                      type="button"
                      className="btn"
                      aria-label={`Correct ${row.label}`}
                      onClick={() => onCorrect(row.id)}
                    >
                      Correct
                    </button>
                  )}
                </div>
              </th>
              {incidents && (
                <td className="entries-incident">{row.incidents}</td>
              )}
              {comments.map((f) => (
                <Answer key={f.code} field={f} row={row} comment />
              ))}
              {answers.map((f) => (
                <Answer key={f.code} field={f} row={row} />
              ))}
              {corrected && <Correction row={row} />}
              <td>{row.scout}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
