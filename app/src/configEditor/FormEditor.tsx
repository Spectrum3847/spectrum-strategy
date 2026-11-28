import { useId, useMemo, useRef, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { useOutbox } from "../outbox/useOutbox";
import { DeliveryLine } from "../scout/ScoutForm";
import { ChangeList } from "./ChangeList";
import {
  configPath,
  type Doc,
  delimiterOf,
  type FormId,
  fieldsOf,
  formName,
  revisionOf,
  sectionsOf,
  textOf,
} from "./doc";
import { reportDrawingOn, setReportDrawing } from "./edit";
import { type EditMode, QuestionList } from "./QuestionList";
import { prepareSave } from "./revise";
import { saveConfig, useConfigSource } from "./source";
import { checkConfigDoc, checkConfigText } from "./validate";

export interface Draft {
  doc: Doc;
  baseRevision: number;
}

const editMode: Record<FormId, EditMode> = {
  scout: "text",
  pit: "full",
  prescout: "view",
};

interface Loaded {
  error: string | null;
  warnings: string[];
  note: string | null;
}

const idle: Loaded = { error: null, warnings: [], note: null };

export function FormEditor({
  form,
  canEdit,
  draft,
  setDraft,
}: {
  form: FormId;
  canEdit: boolean;
  draft: Draft | null;
  setDraft(next: Draft | null): void;
}) {
  const id = useId();
  const auth = useAuth();
  const outbox = useOutbox();
  const { active, teamCopyKnown } = useConfigSource(form);
  const picker = useRef<HTMLInputElement>(null);
  const [loaded, setLoaded] = useState<Loaded>(idle);
  const [pasting, setPasting] = useState(false);
  const [pasteText, setPasteText] = useState("");
  const [showJson, setShowJson] = useState(false);
  const [reviewing, setReviewing] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const shown = draft?.doc ?? active;
  const activeRevision = revisionOf(active);
  const mode = canEdit ? editMode[form] : "view";

  const prepared = useMemo(() => {
    if (!draft) return null;
    const check = checkConfigDoc(draft.doc);
    if (!check.ok) return check;
    return {
      ...prepareSave(draft.doc, active, activeRevision),
      warnings: check.warnings,
    };
  }, [draft, active, activeRevision]);

  const item = outbox.find((i) => i.path === configPath(form));

  const load = (text: string, source: string) => {
    const check = checkConfigText(text);
    if (!check.ok) {
      setLoaded({ error: check.error, warnings: [], note: null });
      return;
    }
    const fields = fieldsOf(check.doc).length;
    const sections = sectionsOf(check.doc).length;
    setDraft({ doc: check.doc, baseRevision: activeRevision });
    setReviewing(false);
    setSaveError(null);
    setLoaded({
      error: null,
      warnings: check.warnings,
      note: `${source}: "${textOf(check.doc.title, "Scout")}" with ${fields} fields in ${sections} sections. Review it below, then save.`,
    });
  };

  const edit = (doc: Doc) => {
    setDraft({ doc, baseRevision: draft?.baseRevision ?? activeRevision });
    setReviewing(false);
    setSaveError(null);
  };

  const discard = () => {
    setDraft(null);
    setReviewing(false);
    setSaveError(null);
    setLoaded(idle);
  };

  const confirmSave = async () => {
    if (!prepared?.ok) return;
    setSaving(true);
    setSaveError(null);
    try {
      await saveConfig(form, prepared.configJson);
      setDraft(null);
      setReviewing(false);
      setLoaded(idle);
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "Could not save.");
    } finally {
      setSaving(false);
    }
  };

  const fieldCount = fieldsOf(shown).length;

  return (
    <div className="ce-form-editor">
      <dl className="rows">
        <dt>Title</dt>
        <dd>{textOf(active.title, "Untitled")}</dd>
        <dt>Revision</dt>
        <dd>{activeRevision}</dd>
        <dt>Sections</dt>
        <dd>{sectionsOf(active).length}</dd>
        <dt>Fields</dt>
        <dd>{fieldsOf(active).length}</dd>
        <dt>Delimiter</dt>
        <dd>
          {delimiterOf(active.delimiter) === "\t"
            ? "Tab"
            : delimiterOf(active.delimiter)}
        </dd>
        {form === "scout" && (
          <>
            <dt>Report drawing</dt>
            <dd>{reportDrawingOn(active) ? "On" : "Off"}</dd>
          </>
        )}
        <dt>Team copy</dt>
        <dd>
          {teamCopyKnown
            ? "Up to date"
            : "Not confirmed yet. This device is using the copy it already holds."}
        </dd>
        {item && (
          <>
            <dt>Last save</dt>
            <dd>
              <DeliveryLine
                delivery={{
                  status: item.status,
                  ...(item.error ? { error: item.error } : {}),
                }}
                signedIn={auth.status === "signed-in"}
              />
            </dd>
          </>
        )}
      </dl>

      {!canEdit && (
        <p className="secondary">
          Your team leads manage this form. It updates on your device when you
          are connected.
        </p>
      )}

      {canEdit && (
        <div className="ce-group">
          <h4>Replace the whole form</h4>
          <p className="secondary">
            Load a QRScout-compatible JSON file. It is checked first and nothing
            is sent until you confirm.
          </p>
          <div className="actions">
            <button
              type="button"
              className="btn"
              onClick={() => picker.current?.click()}
            >
              Upload JSON file
            </button>
            <button
              type="button"
              className="btn"
              aria-expanded={pasting}
              onClick={() => setPasting(!pasting)}
            >
              Paste JSON
            </button>
            <button
              type="button"
              className="btn"
              aria-expanded={showJson}
              onClick={() => setShowJson(!showJson)}
            >
              View current JSON
            </button>
            <input
              ref={picker}
              type="file"
              accept=".json,application/json"
              hidden
              aria-label={`${formName[form]} JSON file`}
              onChange={(e) => {
                const file = e.target.files?.[0];
                e.target.value = "";
                if (file) void file.text().then((t) => load(t, file.name));
              }}
            />
          </div>
          {pasting && (
            <div className="ce-paste">
              <label htmlFor={`${id}-paste`}>Config JSON</label>
              <textarea
                id={`${id}-paste`}
                className="input ce-json"
                rows={10}
                spellCheck={false}
                value={pasteText}
                onChange={(e) => setPasteText(e.target.value)}
              />
              <div className="actions">
                <button
                  type="button"
                  className="btn primary"
                  disabled={pasteText.trim() === ""}
                  onClick={() => load(pasteText.trim(), "Pasted")}
                >
                  Check and load
                </button>
              </div>
            </div>
          )}
          {showJson && (
            <div className="ce-paste">
              <label htmlFor={`${id}-json`}>Current config JSON</label>
              <textarea
                id={`${id}-json`}
                className="input ce-json"
                rows={12}
                readOnly
                spellCheck={false}
                value={JSON.stringify(active, null, 2)}
              />
            </div>
          )}
          {loaded.error && (
            <p className="notice" role="alert">
              Not loaded. {loaded.error}
            </p>
          )}
          {loaded.note && <p className="notice-soft">{loaded.note}</p>}
          {loaded.warnings.map((w) => (
            <p key={w} className="notice-soft">
              {w}
            </p>
          ))}
        </div>
      )}

      {canEdit && draft && prepared && (
        <div className="ce-group" aria-live="polite">
          <h4>Unsaved changes</h4>
          {draft.baseRevision !== activeRevision && (
            <p className="notice-soft">
              The live form changed to revision {activeRevision} while you were
              editing. Saving replaces it with your version.
            </p>
          )}
          {!prepared.ok ? (
            <p className="notice" role="alert">
              Cannot save yet. {prepared.error}
            </p>
          ) : reviewing ? (
            <>
              <p>Saving sends this to every device on the team. It changes:</p>
              <ChangeList changes={prepared.changes} />
              {prepared.warnings.map((w) => (
                <p key={w} className="notice-soft">
                  {w}
                </p>
              ))}
              {saveError && (
                <p className="notice" role="alert">
                  {saveError}
                </p>
              )}
            </>
          ) : (
            <ChangeList changes={prepared.changes} />
          )}
          <div className="actions">
            {prepared.ok && !reviewing && (
              <button
                type="button"
                className="btn primary"
                onClick={() => setReviewing(true)}
              >
                Review and save
              </button>
            )}
            {prepared.ok && reviewing && (
              <>
                <button
                  type="button"
                  className="btn primary"
                  disabled={saving}
                  onClick={() => void confirmSave()}
                >
                  Save to the team
                </button>
                <button
                  type="button"
                  className="btn"
                  onClick={() => setReviewing(false)}
                >
                  Back
                </button>
              </>
            )}
            <button type="button" className="btn" onClick={discard}>
              Discard changes
            </button>
          </div>
        </div>
      )}

      {canEdit && form === "scout" && (
        <label className="ce-check">
          <input
            type="checkbox"
            checked={reportDrawingOn(shown)}
            onChange={(e) => edit(setReportDrawing(shown, e.target.checked))}
          />
          <span>
            Report drawing
            <span className="secondary">
              Show the drawing card at the end of the match form.
            </span>
          </span>
        </label>
      )}

      <div className="ce-group">
        <h4>Questions ({fieldCount})</h4>
        <QuestionList doc={shown} mode={mode} onChange={edit} />
      </div>
    </div>
  );
}
