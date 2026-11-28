import { useId, useState } from "react";
import {
  type Correction,
  maxCorrectedFields,
  maxCorrectionNote,
} from "../data/corrections";
import type { Values } from "../scout/config";
import { FieldInput } from "../scout/fields";
import { sameValue } from "./apply";
import { changedFields, type FieldGroup, visibleFields } from "./fields";

interface Props {
  groups: FieldGroup[];
  values: Values;
  rawValues: Values;
  correction: Correction | null;
  onSave(fields: Values, note: string): Promise<void>;
  onCancel(): void;
}

function unchanged(
  next: Values,
  stored: Values,
  note: string,
  storedNote: string,
) {
  const keys = Object.keys(next);
  return (
    note.trim() === storedNote.trim() &&
    keys.length === Object.keys(stored).length &&
    keys.every((k) => k in stored && sameValue(next[k], stored[k]))
  );
}

export function CorrectionEditor(props: Props) {
  const { groups, values, rawValues, correction, onSave, onCancel } = props;
  const id = useId();
  const [draft, setDraft] = useState<Values>(values);
  const [note, setNote] = useState(correction?.note ?? "");
  const [failed, setFailed] = useState(false);
  const [saving, setSaving] = useState(false);

  const all = groups.flatMap((g) => g.fields);
  const changed = changedFields(all, rawValues, draft);
  const stored = changedFields(all, rawValues, values);
  const tooMany = Object.keys(changed).length > maxCorrectedFields;
  const same = unchanged(changed, stored, note, correction?.note ?? "");

  const patch = (next: Values) => setDraft((d) => ({ ...d, ...next }));

  return (
    <form
      className="correct"
      onSubmit={(e) => {
        e.preventDefault();
        setSaving(true);
        setFailed(false);
        onSave(changed, note).then(
          () => setSaving(false),
          () => {
            setSaving(false);
            setFailed(true);
          },
        );
      }}
    >
      <p className="secondary">
        The scout's own entry stays as it was. Your answers are saved beside it
        and the stats use them.
      </p>
      {groups.map((group, g) => {
        const shown = visibleFields(group.fields, draft);
        if (shown.length === 0) return null;
        return (
          <fieldset key={group.name || g} className="correct-group">
            {group.name !== "" && <legend>{group.name}</legend>}
            {shown.map((field) => (
              <div key={field.code} className="correct-field">
                <span className="label">{field.title}</span>
                <FieldInput
                  field={field}
                  values={draft}
                  schedule={[]}
                  resetToken={0}
                  onChange={(code, value) => patch({ [code]: value })}
                  onPatch={patch}
                />
                {field.code in changed && (
                  <span className="secondary">Changed</span>
                )}
              </div>
            ))}
          </fieldset>
        );
      })}
      <label className="correct-note" htmlFor={`${id}-note`}>
        <span className="label">Why (optional)</span>
        <textarea
          id={`${id}-note`}
          className="input"
          rows={3}
          maxLength={maxCorrectionNote}
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
      </label>
      {tooMany && (
        <p className="notice" role="status">
          {`A correction holds up to ${maxCorrectedFields} changed answers.`}
        </p>
      )}
      {failed && (
        <p className="notice" role="status">
          Could not save on this device. Try again.
        </p>
      )}
      <div className="actions">
        <button
          type="submit"
          className="btn primary"
          disabled={same || tooMany || saving}
        >
          Save correction
        </button>
        <button type="button" className="btn" onClick={onCancel}>
          Cancel
        </button>
      </div>
    </form>
  );
}
