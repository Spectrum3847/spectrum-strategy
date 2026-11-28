import { type ReactNode, useCallback, useEffect, useState } from "react";
import { Link } from "react-router";
import { clearCache, writeCache } from "../data/cache";
import {
  emptyRequiredFields,
  isVisible,
  type ScoutConfig,
  type Values,
} from "../scout/config";
import {
  Check,
  type Delivery,
  DeliveryLine,
  FieldRow,
} from "../scout/ScoutForm";
import "./forms.css";

export interface EntryFormProps {
  config: ScoutConfig;
  initial: Values;
  draftKey: string;
  restored: boolean;
  entryId: string;
  title: string;
  subtitle?: string;
  back: { to: string; label: string };
  status: string[];
  signedIn: boolean;
  online: boolean;
  unsent: number;
  deliveryOf(id: string): Delivery | undefined;
  save(values: Values): Promise<void>;
  check?(values: Values): string | null;
  notice?: ReactNode;
  above?(api: { values: Values; patch(p: Values): void }): ReactNode;
  beside?(values: Values): ReactNode;
  after?: ReactNode;
  savedNote?: ReactNode;
  savedTitle: string;
}

const noSchedule: never[] = [];

export function EntryForm(props: EntryFormProps) {
  const { config, draftKey, save, check } = props;
  const [values, setValues] = useState<Values>(props.initial);
  const [touched, setTouched] = useState(false);
  const [warned, setWarned] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState(false);
  const empty = emptyRequiredFields(config, values);
  const beside = props.beside?.(values);

  const change = useCallback((code: string, value: unknown) => {
    setValues((v) => ({ ...v, [code]: value }));
    setTouched(true);
    setError(null);
    setWarned(false);
  }, []);
  const patch = useCallback((p: Values) => {
    setValues((v) => ({ ...v, ...p }));
    setTouched(true);
  }, []);

  useEffect(() => {
    if (touched && !done) writeCache(draftKey, values);
  }, [values, touched, done, draftKey]);

  async function submit() {
    if (!props.signedIn) {
      setError("Sign in to save this entry.");
      return;
    }
    const problem = check?.(values) ?? null;
    if (problem) {
      setError(problem);
      return;
    }
    if (empty.length > 0 && !warned) {
      setWarned(true);
      return;
    }
    setSaving(true);
    try {
      await save(values);
      clearCache(draftKey);
      setError(null);
      setWarned(false);
      setDone(true);
    } catch {
      setError(
        "Could not save the entry. Nothing was recorded, so do not leave this screen.",
      );
    } finally {
      setSaving(false);
    }
  }

  const head = (
    <header className="scout-head">
      <div className="match-line">
        <Link className="btn" to={props.back.to}>
          {props.back.label}
        </Link>
        <h1 className="match-num">{props.title}</h1>
        {props.subtitle && <span className="form-sub">{props.subtitle}</span>}
      </div>
      <p className="status-line secondary" aria-live="polite">
        {props.status.map((s) => (
          <span key={s}>{s}</span>
        ))}
        <span>{props.online ? "Online" : "Offline"}</span>
        {props.unsent > 0 && <span>{props.unsent} unsent</span>}
      </p>
    </header>
  );

  if (done) {
    return (
      <div className="scout">
        {head}
        <div className="scout-body saved-view">
          <Check />
          <h2 className="saved-title">{props.savedTitle}</h2>
          <p>
            <DeliveryLine
              delivery={props.deliveryOf(props.entryId)}
              signedIn={props.signedIn}
            />
          </p>
          {props.savedNote}
          <button
            type="button"
            className="btn big"
            onClick={() => {
              setTouched(false);
              setDone(false);
            }}
          >
            Edit this entry
          </button>
        </div>
        <footer className="scout-foot">
          <Link className="btn primary big" to={props.back.to}>
            {props.back.label}
          </Link>
        </footer>
      </div>
    );
  }

  return (
    <div className="scout">
      {head}
      <div className="scout-body">
        {props.restored && (
          <p className="notice-soft">Restored your unsaved answers.</p>
        )}
        {props.notice}
        {props.above?.({ values, patch })}
        <div className="entry-split" data-beside={beside ? "" : undefined}>
          {beside && <div className="entry-beside">{beside}</div>}
          <div className="entry-main">
            {config.sections.map((section, i) => {
              const fields = section.fields.filter((f) => isVisible(f, values));
              if (fields.length === 0) return null;
              const id = `section-${i}`;
              return (
                <section key={id} aria-labelledby={id}>
                  <h2 id={id} className="form-section">
                    {section.name || "Details"}
                  </h2>
                  {fields.map((field) => (
                    <FieldRow
                      key={field.code}
                      field={field}
                      values={values}
                      schedule={noSchedule}
                      resetToken={0}
                      onChange={change}
                      onPatch={patch}
                    />
                  ))}
                </section>
              );
            })}
          </div>
        </div>
        {props.after}
      </div>
      <footer className="scout-foot">
        {error && (
          <p className="notice" role="alert">
            {error}
          </p>
        )}
        {warned && empty.length > 0 && (
          <div className="notice" role="alert">
            <p>Required, still empty:</p>
            <ul className="plain">
              {empty.map((f) => (
                <li key={f.code}>{f.title}</li>
              ))}
            </ul>
          </div>
        )}
        <div className="foot-row foot-two">
          <Link className="btn" to={props.back.to}>
            {props.back.label}
          </Link>
          <button
            type="button"
            className="btn primary"
            disabled={saving || !props.signedIn}
            onClick={() => void submit()}
          >
            {!props.signedIn
              ? "Sign in to save"
              : warned && empty.length > 0
                ? "Save anyway"
                : "Save"}
          </button>
        </div>
      </footer>
    </div>
  );
}
