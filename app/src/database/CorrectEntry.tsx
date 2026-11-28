import { useEffect, useMemo, useRef, useState } from "react";
import type { Corrected } from "../corrections/apply";
import { CorrectionEditor } from "../corrections/CorrectionEditor";
import { correctableGroups } from "../corrections/fields";
import { entryLabel } from "../corrections/rows";
import {
  CorrectionDelivery,
  saveEntryCorrection,
  useCorrector,
} from "../corrections/useCorrect";
import type { EventEntry } from "../data/parse";
import type { ScoutConfig, Values } from "../scout/config";
import "../corrections/corrections.css";

export function CorrectEntry({
  entry,
  eventKey,
  config,
  backLabel = "Back to the database",
  onBack,
}: {
  entry: Corrected<EventEntry>;
  eventKey: string;
  config: ScoutConfig;
  backLabel?: string;
  onBack: () => void;
}) {
  const { canCorrect, author } = useCorrector(eventKey);
  const groups = useMemo(() => correctableGroups(config), [config]);
  const [saved, setSaved] = useState(false);
  const [failed, setFailed] = useState(false);
  const save = (fields: Values, note: string) =>
    saveEntryCorrection(
      entry,
      entry.teamNumber,
      eventKey,
      author,
      fields,
      note,
    );
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => heading.current?.focus(), []);
  const title = `Correct team ${entry.teamNumber}, ${entryLabel(entry)}`;

  return (
    <section className="db-correct" aria-labelledby="db-correct-h">
      <div className="actions">
        <button type="button" className="btn" onClick={onBack}>
          {backLabel}
        </button>
      </div>
      <h2 id="db-correct-h" ref={heading} tabIndex={-1}>
        {title}
      </h2>
      <p className="secondary">
        {entry.scoutName || "Unnamed scout"}
        {entry.correction ? ", already corrected once" : ""}
      </p>
      {!canCorrect ? (
        <p className="notice" role="status">
          Corrections need a signed-in lead and an event.
        </p>
      ) : saved ? (
        <>
          <p role="status">Correction saved on this device.</p>
          <CorrectionDelivery entryId={entry.id} />
        </>
      ) : (
        <>
          <CorrectionEditor
            groups={groups}
            values={entry.fieldValues}
            rawValues={entry.rawValues}
            correction={entry.correction}
            onSave={async (fields, note) => {
              await save(fields, note);
              setSaved(true);
            }}
            onCancel={onBack}
          />
          {entry.corrected.length > 0 && (
            <div className="actions">
              <button
                type="button"
                className="btn"
                onClick={() => {
                  setFailed(false);
                  save({}, "").then(
                    () => setSaved(true),
                    () => setFailed(true),
                  );
                }}
              >
                Remove correction
              </button>
            </div>
          )}
          {failed && (
            <p className="notice" role="status">
              Could not save on this device. Try again.
            </p>
          )}
        </>
      )}
    </section>
  );
}
