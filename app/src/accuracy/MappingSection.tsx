import { useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { dismissItem } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { DeliveryState } from "../shifts/MyShifts";
import {
  mappingPath,
  mappingRows,
  mappingText,
  parseMappingText,
  starterMapping,
} from "./mapping";
import { saveMapping, useAccuracyMapping } from "./useAccuracyData";

export function MappingSection() {
  const auth = useAuth();
  const { status, mapping } = useAccuracyMapping(auth.status === "signed-in");
  const outbox = useOutbox();
  const [draft, setDraft] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const item = outbox.find((i) => i.path === mappingPath);
  const delivery = item && {
    id: item.id,
    status: item.status,
    ...(item.error ? { error: item.error } : {}),
  };

  const edit = () => {
    setError(null);
    setDraft(mappingText(mapping ?? starterMapping(new Date().getFullYear())));
  };

  const save = async () => {
    if (draft === null) return;
    const parsed = parseMappingText(draft);
    if (!parsed.ok) {
      setError(parsed.error);
      return;
    }
    try {
      await saveMapping(parsed.doc);
      setDraft(null);
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not save the mapping.");
    }
  };

  return (
    <details className="acc-mapping">
      <summary>Alert mapping</summary>
      <div className="acc-mapping-body">
        <p className="secondary">
          Which scout fields the alert job compares with Statbotics, and how
          strict it is. It does not change the estimates above. A save reaches
          the job within five minutes.
        </p>
        {status === "failed" && (
          <p className="notice" role="alert">
            The mapping could not be read.
          </p>
        )}
        {status === "loading" && (
          <p className="secondary">Loading the mapping.</p>
        )}
        {status === "ready" && !mapping && (
          <p className="secondary">No mapping configured yet.</p>
        )}
        {mapping && draft === null && (
          <dl className="acc-rows">
            {mappingRows(mapping).map(([label, value]) => (
              <div key={label}>
                <dt>{label}</dt>
                <dd>{value}</dd>
              </div>
            ))}
          </dl>
        )}
        {draft !== null && (
          <div className="acc-edit">
            <label className="field-name" htmlFor="acc-mapping-json">
              Mapping JSON
            </label>
            <textarea
              id="acc-mapping-json"
              className="input acc-json"
              value={draft}
              spellCheck={false}
              rows={16}
              onChange={(e) => setDraft(e.target.value)}
            />
            {error && (
              <p className="notice" role="alert">
                {error}
              </p>
            )}
            <div className="actions">
              <button type="button" className="btn primary" onClick={save}>
                Save
              </button>
              <button
                type="button"
                className="btn"
                onClick={() => setDraft(null)}
              >
                Cancel
              </button>
            </div>
          </div>
        )}
        {draft === null && status === "ready" && (
          <div className="actions">
            <button type="button" className="btn" onClick={edit}>
              {mapping ? "Edit mapping" : "Create mapping"}
            </button>
          </div>
        )}
        <div aria-live="polite">
          <DeliveryState delivery={delivery} onDismiss={dismissItem} />
        </div>
      </div>
    </details>
  );
}
