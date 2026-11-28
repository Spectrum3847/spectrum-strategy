import { useEffect, useId, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { SketchEditor } from "../board/Sketch";
import {
  emptySketch,
  type Sketch,
  sketchIsEmpty,
  strokesToJson,
} from "../board/sketch";
import { clearCache, readCache, writeCache } from "../data/cache";
import { useTrexReports } from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { enqueueWrite } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { Check, DeliveryLine } from "../scout/ScoutForm";
import { deliveryOf, reportPath } from "./delivery";
import { limits, problemWith, reportDocument } from "./document";
import { RatingInput } from "./RatingInput";
import { eventNameFor } from "./reports";
import { TrexFrame } from "./TrexFrame";
import { traits } from "./traits";

const draftKey = "ss.trex.draft";

interface Fields {
  trait: string;
  team: string;
  match: string;
  eventName: string | null;
  rating: number | null;
  report: string;
}

const blank: Fields = {
  trait: traits[0]?.key ?? "",
  team: "",
  match: "",
  eventName: null,
  rating: null,
  report: "",
};

const digits = (s: string) => s.replace(/\D/g, "");

export function TrexReportForm() {
  const auth = useAuth();
  const { eventKey, teams } = useTbaEvent();
  const reports = useTrexReports();
  const outbox = useOutbox();
  const [start] = useState(() => {
    const stored = readCache<Partial<Fields>>(draftKey);
    return { fields: { ...blank, ...stored }, restored: stored !== null };
  });
  const [fields, setFields] = useState<Fields>(start.fields);
  const [restored, setRestored] = useState(start.restored);
  const [sketch, setSketch] = useState<Sketch>(emptySketch);
  const [drawingOpen, setDrawingOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState<{ id: string; team: number } | null>(null);
  const ids = {
    team: useId(),
    match: useId(),
    event: useId(),
    report: useId(),
  };

  const eventName = fields.eventName ?? eventNameFor(reports.items, eventKey);
  const trait = traits.find((t) => t.key === fields.trait) ?? traits[0];
  const teamNumber = Number(fields.team);
  const nickname = teams.find((t) => t.number === teamNumber)?.nickname;
  const signedIn = auth.status === "signed-in" && auth.uid !== null;

  useEffect(() => {
    if (saved !== null) return;
    const empty =
      fields.team === "" &&
      fields.match === "" &&
      fields.rating === null &&
      fields.report === "";
    if (empty) clearCache(draftKey);
    else writeCache(draftKey, fields);
  }, [fields, saved]);

  const change = (patch: Partial<Fields>) => {
    setFields((f) => ({ ...f, ...patch }));
    setError(null);
    setRestored(false);
  };

  async function submit() {
    if (!signedIn || auth.uid === null) {
      setError("Sign in to save this report.");
      return;
    }
    const problem = problemWith({
      trait: fields.trait,
      team: fields.team,
      match: fields.match,
      eventName,
      rating: fields.rating,
      report: fields.report,
    });
    if (problem || fields.rating === null) {
      setError(problem ?? "Pick a rating from 1 to 5.");
      return;
    }
    setSaving(true);
    try {
      const id = crypto.randomUUID();
      await enqueueWrite(
        reportPath(id),
        reportDocument({
          id,
          trait: fields.trait,
          team: teamNumber,
          match: Number(fields.match),
          eventName,
          eventKey,
          rating: fields.rating,
          report: fields.report,
          strokes: strokesToJson(sketch.auton),
          authorUid: auth.uid,
          authorDisplayName: auth.displayName ?? "",
          now: new Date(),
        }),
        `T-REx, team ${teamNumber}`,
      );
      clearCache(draftKey);
      setSaved({ id, team: teamNumber });
    } catch {
      setError(
        "Could not save the report. Nothing was recorded, so do not leave this screen.",
      );
    } finally {
      setSaving(false);
    }
  }

  if (saved) {
    return (
      <TrexFrame>
        <div className="saved-view" role="status">
          <Check />
          <h2 className="saved-title">Report saved for team {saved.team}</h2>
          <p>
            <DeliveryLine
              delivery={deliveryOf(outbox, saved.id)}
              signedIn={signedIn}
            />
          </p>
          <button
            type="button"
            className="btn primary big"
            onClick={() => {
              setFields((f) => ({
                ...blank,
                trait: f.trait,
                eventName: f.eventName,
              }));
              setRestored(false);
              setSketch(emptySketch());
              setDrawingOpen(false);
              setSaved(null);
            }}
          >
            New report
          </button>
        </div>
      </TrexFrame>
    );
  }

  return (
    <TrexFrame>
      <form
        className="trex-form"
        onSubmit={(e) => {
          e.preventDefault();
          void submit();
        }}
      >
        {restored && (
          <p className="notice-soft">Restored your unsaved report.</p>
        )}

        <fieldset className="chips">
          <legend className="field-name">Trait</legend>
          {traits.map((t) => (
            <button
              key={t.key}
              type="button"
              className="chip"
              aria-pressed={t.key === fields.trait}
              onClick={() => change({ trait: t.key })}
            >
              {t.label}
            </button>
          ))}
        </fieldset>

        {trait && (
          <details className="trex-help">
            <summary>Lookout notes for {trait.label}</summary>
            <p>{trait.instructions}</p>
          </details>
        )}

        <div className="trex-pair">
          <div className="trex-field">
            <label className="field-name" htmlFor={ids.team}>
              Team number
            </label>
            <input
              id={ids.team}
              className="input"
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              autoComplete="off"
              list={`${ids.team}-teams`}
              value={fields.team}
              onChange={(e) => change({ team: digits(e.target.value) })}
            />
            <datalist id={`${ids.team}-teams`}>
              {teams.map((t) => (
                <option key={t.number} value={t.number}>
                  {t.nickname}
                </option>
              ))}
            </datalist>
            {nickname && <span className="secondary">{nickname}</span>}
          </div>
          <div className="trex-field">
            <label className="field-name" htmlFor={ids.match}>
              Match number
            </label>
            <input
              id={ids.match}
              className="input"
              type="text"
              inputMode="numeric"
              pattern="[0-9]*"
              autoComplete="off"
              value={fields.match}
              onChange={(e) => change({ match: digits(e.target.value) })}
            />
          </div>
        </div>

        <div className="trex-field">
          <label className="field-name" htmlFor={ids.event}>
            Event
          </label>
          <input
            id={ids.event}
            className="input"
            type="text"
            autoComplete="off"
            maxLength={limits.eventName}
            value={eventName}
            onChange={(e) => change({ eventName: e.target.value })}
          />
        </div>

        <RatingInput
          value={fields.rating}
          onChange={(rating) => change({ rating })}
        />

        <div className="trex-field">
          <label className="field-name" htmlFor={ids.report}>
            Report
          </label>
          <textarea
            id={ids.report}
            className="input trex-text"
            value={fields.report}
            onChange={(e) => change({ report: e.target.value })}
          />
          <span className="secondary">
            {fields.report.trim().length} of {limits.report} characters
          </span>
        </div>

        <div className="trex-field">
          <button
            type="button"
            className="btn"
            aria-expanded={drawingOpen}
            onClick={() => setDrawingOpen((o) => !o)}
          >
            {drawingOpen
              ? "Hide drawing"
              : sketchIsEmpty(sketch)
                ? "Add drawing"
                : "Show drawing"}
          </button>
          {drawingOpen && (
            <SketchEditor
              title="Drawing"
              surface="Trait drawing"
              value={sketch}
              phased={false}
              onChange={setSketch}
            />
          )}
        </div>

        {error && (
          <p className="notice" role="alert">
            {error}
          </p>
        )}
        <button
          type="submit"
          className="btn primary big"
          disabled={saving || !signedIn}
        >
          {signedIn ? "Save report" : "Sign in to save"}
        </button>
      </form>
    </TrexFrame>
  );
}
