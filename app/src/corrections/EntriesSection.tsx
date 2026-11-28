import { useMemo, useState } from "react";
import type { CorrectionAuthor } from "../data/corrections";
import type { EventEntry } from "../data/parse";
import { CorrectEntry } from "../database/CorrectEntry";
import type { ScoutConfig, Values } from "../scout/config";
import { when } from "../team/Sections";
import { useWide } from "../ui/useWide";
import type { Corrected } from "./apply";
import { CorrectionEditor } from "./CorrectionEditor";
import { EntriesTable } from "./EntriesTable";
import { correctableGroups, type FieldGroup } from "./fields";
import { answerRows, entryLabel, newestFirst } from "./rows";
import {
  CorrectionDelivery,
  saveEntryCorrection,
  useCorrector,
} from "./useCorrect";
import "./corrections.css";

type Entry = Corrected<EventEntry>;

interface RowProps {
  entry: Entry;
  team: number;
  eventKey: string;
  groups: FieldGroup[];
  canCorrect: boolean;
  author: CorrectionAuthor;
}

function EntryRow({
  entry,
  team,
  eventKey,
  groups,
  canCorrect,
  author,
}: RowProps) {
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const [failed, setFailed] = useState(false);
  const label = entryLabel(entry);
  const fixed = entry.corrected.length > 0;
  const rows = useMemo(
    () =>
      answerRows(
        groups.flatMap((g) => g.fields),
        entry,
      ),
    [groups, entry],
  );
  const by = entry.correction
    ? [
        entry.correction.authorDisplayName,
        entry.correction.updatedMs > 0
          ? when(new Date(entry.correction.updatedMs).toISOString())
          : "",
      ]
        .filter((p) => p !== "")
        .join(", ")
    : "";

  const save = (fields: Values, note: string) =>
    saveEntryCorrection(entry, team, eventKey, author, fields, note);

  return (
    <details
      className="team-details"
      onToggle={(e) => setOpen(e.currentTarget.open)}
    >
      <summary className="entry-summary">
        <span className="entry-label">{label}</span>
        <span className="secondary">{entry.scoutName || "Unnamed scout"}</span>
        {fixed && <span className="corrected-tag">Corrected</span>}
      </summary>
      {!open ? null : editing ? (
        <CorrectionEditor
          groups={groups}
          values={entry.fieldValues}
          rawValues={entry.rawValues}
          correction={entry.correction}
          onSave={async (fields, note) => {
            await save(fields, note);
            setEditing(false);
          }}
          onCancel={() => setEditing(false)}
        />
      ) : (
        <>
          {rows.length === 0 ? (
            <p className="secondary">This entry has no answers.</p>
          ) : (
            <dl className="team-answers">
              {rows.map((row) => (
                <div key={row.code} className="team-answer">
                  <dt>{row.title}</dt>
                  <dd>
                    {row.value === "" ? "Blank" : row.value}
                    {row.was !== null && (
                      <>
                        {" "}
                        <span className="corrected-tag">Corrected</span>
                        <span className="secondary entry-was">
                          {`Scout entered ${row.was === "" ? "nothing" : row.was}`}
                        </span>
                      </>
                    )}
                  </dd>
                </div>
              ))}
            </dl>
          )}
          {fixed && entry.correction && (
            <div className="entry-correction">
              {by !== "" && <p className="secondary">Corrected by {by}</p>}
              {entry.correction.note !== "" && (
                <p className="entry-note">{entry.correction.note}</p>
              )}
            </div>
          )}
          {canCorrect && (
            <div className="actions">
              <button
                type="button"
                className="btn"
                onClick={() => setEditing(true)}
              >
                {fixed ? "Edit correction" : "Correct"}
              </button>
              {fixed && (
                <button
                  type="button"
                  className="btn"
                  onClick={() => {
                    setFailed(false);
                    save({}, "").catch(() => setFailed(true));
                  }}
                >
                  Remove correction
                </button>
              )}
            </div>
          )}
          {failed && (
            <p className="notice" role="status">
              Could not save on this device. Try again.
            </p>
          )}
          <CorrectionDelivery entryId={entry.id} />
        </>
      )}
    </details>
  );
}

export function EntriesSection({
  team,
  eventKey,
  config,
  entries,
}: {
  team: number;
  eventKey: string;
  config: ScoutConfig;
  entries: Entry[];
}) {
  const wide = useWide();
  const { canCorrect, author } = useCorrector(eventKey);
  const groups = useMemo(() => correctableGroups(config), [config]);
  const sorted = useMemo(() => newestFirst(entries), [entries]);
  const [editing, setEditing] = useState<string | null>(null);
  const entry = wide ? entries.find((e) => e.id === editing) : undefined;
  return (
    <section className="team-section" aria-labelledby="team-entries">
      <h2 id="team-entries">Scout entries</h2>
      {sorted.length === 0 ? (
        <p className="secondary">No entries to show yet.</p>
      ) : entry ? (
        <CorrectEntry
          entry={entry}
          eventKey={eventKey}
          config={config}
          backLabel="Back to the entries"
          onBack={() => setEditing(null)}
        />
      ) : wide ? (
        <EntriesTable
          entries={entries}
          config={config}
          onCorrect={canCorrect ? setEditing : undefined}
        />
      ) : (
        <ul className="team-list">
          {sorted.map((entry) => (
            <li key={entry.id}>
              <EntryRow
                entry={entry}
                team={team}
                eventKey={eventKey}
                groups={groups}
                canCorrect={canCorrect}
                author={author}
              />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
