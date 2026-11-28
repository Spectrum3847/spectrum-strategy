import { useMemo, useState } from "react";
import { EditNote } from "../corrections/EditNote";
import { editInfo } from "../corrections/history";
import { answerRows } from "../corrections/rows";
import { when } from "../team/Sections";
import { TeamLink } from "../ui/TeamLink";
import {
  type BrowseProps,
  FlagBadge,
  MatchLink,
  RowActions,
  Station,
} from "./DbTable";
import type { DbRow } from "./rows";

function EditedBy({ row, code }: { row: DbRow; code: string }) {
  const edit = editInfo(row.entry?.correction ?? null, code);
  return edit && <EditNote edit={edit} className="secondary entry-was" />;
}

function Answers({
  row,
  fields,
}: Pick<BrowseProps, "fields"> & { row: DbRow }) {
  const [open, setOpen] = useState(false);
  const rows = useMemo(
    () =>
      open
        ? answerRows(fields, {
            fieldValues: row.values,
            rawValues: row.rawValues,
            corrected: row.corrected,
          })
        : [],
    [open, fields, row],
  );
  return (
    <details onToggle={(e) => setOpen(e.currentTarget.open)}>
      <summary className="db-summary">Answers</summary>
      {open &&
        (rows.length === 0 ? (
          <p className="secondary">This entry has no answers.</p>
        ) : (
          <dl className="team-answers">
            {rows.map((r) => (
              <div key={r.code} className="team-answer">
                <dt>{r.title}</dt>
                <dd>
                  {r.value === "" ? "Blank" : r.value}
                  {r.was !== null && (
                    <>
                      {" "}
                      <span className="corrected-tag">Corrected</span>
                      <span className="secondary entry-was">
                        {`Scout entered ${r.was === "" ? "nothing" : r.was}`}
                      </span>
                      <EditedBy row={row} code={r.code} />
                    </>
                  )}
                </dd>
              </div>
            ))}
          </dl>
        ))}
    </details>
  );
}

export function DbList({
  kind,
  rows,
  fields,
  onCorrect,
  onHistory,
  remover,
}: BrowseProps) {
  return (
    <ul className="db-list">
      {rows.map((row) => (
        <li key={row.id} className="db-item" data-flag={row.flags[0]?.kind}>
          <div className="db-item-head">
            {kind === "match" && (
              <strong className="db-match">
                <MatchLink row={row} />
              </strong>
            )}
            {row.team > 0 ? <TeamLink team={row.team} /> : <span>?</span>}
            <Station station={row.station} />
            <FlagBadge row={row} />
            {row.incidents !== "" && (
              <span className="db-incident">{row.incidents}</span>
            )}
            {row.corrected.length > 0 && (
              <span className="corrected-tag">Corrected</span>
            )}
          </div>
          <p className="secondary">
            {[
              row.scout || "Unnamed scout",
              kind === "match" ? "" : row.event,
              kind === "match" ? "" : when(row.updatedAt),
            ]
              .filter((p) => p !== "")
              .join(", ")}
          </p>
          <Answers row={row} fields={fields} />
          {(onCorrect || onHistory || remover) && (
            <div className="actions">
              <RowActions
                row={row}
                onCorrect={onCorrect}
                onHistory={onHistory}
                remover={remover}
              />
            </div>
          )}
        </li>
      ))}
    </ul>
  );
}
