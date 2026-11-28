import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { SketchEditor } from "../board/Sketch";
import {
  emptySketch,
  type Sketch,
  sketchFromJson,
  sketchToJson,
} from "../board/sketch";
import type { PitEntry } from "../data/parse";
import type { OutboxStatus } from "../outbox/confirm";
import { DeleteButton } from "../ui/DeleteButton";
import { CreditBar } from "./CreditBar";
import {
  allFields,
  allianceFromStation,
  emptyRequiredFields,
  isVisible,
  labelForStored,
  normalizeStation,
  type ScoutConfig,
  type ScoutField,
  selectedKeys,
  type Values,
} from "./config";
import {
  creditFor,
  matchNumberOf,
  type ScoutShifts,
  type StandIn,
  startStandIn,
} from "./credit";
import { entryDocument, extractTeam, matchIdFor } from "./entry";
import { FieldInput } from "./fields";
import {
  applySchedule,
  type FormState,
  initForm,
  matchCode,
  resetForNext,
  setValue,
  stationCode,
} from "./formState";
import { eventLinkMessage } from "./link";
import { draftStore, matchRefOf, type SavedEntry } from "./local";
import { PitBar } from "./PitBar";
import { QrSheet } from "./QrSheet";
import { encodeQrScout } from "./qr";
import {
  knownRefs,
  type RemoteEntry,
  resolveMatchKey,
  type ScheduledMatch,
  stationOf,
} from "./schedule";

export interface Delivery {
  status: OutboxStatus;
  error?: string;
  training?: boolean;
}

export interface ScoutFormProps {
  config: ScoutConfig;
  schedule: ScheduledMatch[];
  eventKey: string;
  deviceStation: string | null;
  stationLocked?: boolean;
  shifts?: ScoutShifts | null;
  standIn?: StandIn | null;
  onStandIn?(standIn: StandIn | null): void;
  author: { uid: string | null; displayName: string | null };
  online: boolean;
  saved: SavedEntry[];
  remote?: RemoteEntry[];
  unsent: { pending: number; refused: number };
  deliveryOf(entryId: string): Delivery | undefined;
  persist(doc: Record<string, unknown>, entry: SavedEntry): Promise<void>;
  remove?(entry: SavedEntry): Promise<void>;
  onStation(station: string): void;
  onScan?(): void;
  pit?: { entries: readonly PitEntry[]; config: ScoutConfig };
}

const deliveryText: Record<OutboxStatus, string> = {
  "on-device": "On this device",
  sending: "Sending",
  "in-database": "In the database",
  refused: "Refused",
};

export function DeliveryLine({
  delivery,
  signedIn,
}: {
  delivery: Delivery | undefined;
  signedIn: boolean;
}) {
  if (!delivery) return <span className="state">Not in the outbox</span>;
  if (delivery.training) {
    return (
      <span className="state" data-state="training">
        Training only, not sent
      </span>
    );
  }
  const waiting =
    !signedIn &&
    (delivery.status === "on-device" || delivery.status === "sending");
  return (
    <span className="state" data-state={delivery.status}>
      {waiting ? "Waiting for sign-in" : deliveryText[delivery.status]}
      {delivery.error ? `: ${delivery.error}` : ""}
    </span>
  );
}

export function Check() {
  return (
    <svg
      className="big-check"
      viewBox="0 0 48 48"
      aria-hidden="true"
      focusable="false"
    >
      <circle cx="24" cy="24" r="22" />
      <path d="M13 25l8 8 14-17" />
    </svg>
  );
}

export function answerText(field: ScoutField, value: unknown): string {
  switch (field.type) {
    case "boolean":
      return value === true ? "Yes" : "No";
    case "select":
      return labelForStored(field, value);
    case "checkboxSelect":
      return selectedKeys(value)
        .map((k) => labelForStored(field, k))
        .join(", ");
    case "tbaTeamAndRobot":
      return typeof value === "object" && value !== null
        ? String((value as Record<string, unknown>).teamNumber ?? "")
        : "";
    default:
      return value === null || value === undefined ? "" : String(value);
  }
}

export function ScoutForm(props: ScoutFormProps) {
  const { config, schedule, saved, author, remote } = props;
  const ctx = useMemo(
    () => ({
      config,
      schedule,
      saved: knownRefs(saved, remote ?? []),
    }),
    [config, schedule, saved, remote],
  );
  const fingerprint = useMemo(
    () =>
      JSON.stringify(
        config.sections.map((s) => [s.name, s.fields.map((f) => f.code)]),
      ),
    [config],
  );
  const [form, setForm] = useState<FormState>(() => {
    const start = initForm(ctx, props.deviceStation);
    const draft = draftStore.get(fingerprint);
    return draft
      ? {
          ...start,
          values: { ...start.values, ...draft },
          matchFresh: false,
          matchFromAnchor: false,
        }
      : start;
  });
  const [sketch, setSketch] = useState<Sketch>(() =>
    sketchFromJson(draftStore.getStrokes(fingerprint)),
  );
  const [step, setStep] = useState(0);
  const [resetToken, setResetToken] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const [warned, setWarned] = useState(false);
  const [saving, setSaving] = useState(false);
  const [done, setDone] = useState<SavedEntry | null>(null);
  const [qrFor, setQrFor] = useState<SavedEntry | null>(null);
  const closeQr = useCallback(() => setQrFor(null), []);

  useEffect(() => {
    if (!done) setForm((f) => applySchedule(f, ctx));
  }, [ctx, done]);

  useEffect(() => {
    if (done) return;
    const trackerPrefixes = allFields(config)
      .filter((f) => f.type === "actionTracker")
      .map((f) => `${f.code}_`);
    const values = Object.fromEntries(
      Object.entries(form.values).filter(
        ([k]) => !trackerPrefixes.some((p) => k.startsWith(p)),
      ),
    );
    draftStore.set(fingerprint, values, sketchToJson(sketch));
  }, [form.values, sketch, fingerprint, config, done]);

  const sections = config.sections;
  const drawingOn = config.reportDrawing !== false;
  const reviewStep = sections.length;
  const { values } = form;
  const station = stationOf(values);
  const alliance = allianceFromStation(normalizeStation(station) ?? "");
  const team = extractTeam(config, values);
  const typedMatch = String(values[matchCode] ?? "").trim();
  const matchNumber = matchNumberOf(typedMatch);
  const creditStation = props.stationLocked ? props.deviceStation : null;
  const credit = creditFor({
    shifts: props.shifts ?? null,
    station: creditStation,
    match: matchNumber,
    eventKey: props.eventKey,
    standIn: props.standIn ?? null,
  });

  const change = useCallback(
    (code: string, value: unknown) => {
      setError(null);
      setWarned(false);
      setForm((f) => setValue(f, ctx, code, value));
      if (code === stationCode && typeof value === "string") {
        const normalized = normalizeStation(value);
        if (normalized) props.onStation(normalized);
      }
    },
    [ctx, props.onStation],
  );

  const patch = useCallback((p: Record<string, unknown>) => {
    setForm((f) => ({ ...f, values: { ...f.values, ...p } }));
  }, []);

  const goTo = (n: number) => {
    setStep(n);
    window.scrollTo?.({ top: 0 });
  };

  const empty = emptyRequiredFields(config, values);
  const stepOfField = (code: string) =>
    sections.findIndex((s) => s.fields.some((f) => f.code === code));

  async function save() {
    if (!author.uid) {
      setError("Sign in to save this entry.");
      return;
    }
    if (typedMatch === "") {
      setError("Enter the match number before saving.");
      goTo(Math.max(0, stepOfField(matchCode)));
      return;
    }
    if (team <= 0) {
      setError("Enter the team number before saving.");
      const teamField = allFields(config).find(
        (f) => f.type === "tbaTeamAndRobot" || f.code === "pTnumber",
      );
      goTo(Math.max(0, stepOfField(teamField?.code ?? "")));
      return;
    }
    if (empty.length > 0 && !warned) {
      setWarned(true);
      goTo(reviewStep);
      return;
    }
    setSaving(true);
    try {
      const tbaMatchKey = resolveMatchKey(typedMatch, schedule);
      const matchRef = matchRefOf(tbaMatchKey, props.eventKey, typedMatch);
      const existing = saved.find(
        (e) => e.matchRef === matchRef && e.team === team,
      );
      const id = existing?.id ?? crypto.randomUUID();
      const now = new Date();
      const matchId = matchIdFor(tbaMatchKey, props.eventKey, typedMatch);
      const doc = entryDocument({
        id,
        config,
        values,
        matchId,
        tbaMatchKey,
        authorUid: author.uid,
        authorDisplayName: author.displayName ?? "",
        ...(credit ? { scoutedBy: credit } : {}),
        strokesByPhase: drawingOn ? sketchToJson(sketch) : null,
        now,
        ...(existing ? { createdAt: existing.createdAt } : {}),
      });
      const entry: SavedEntry = {
        id,
        matchId,
        matchRef,
        matchNumber: typedMatch,
        team,
        tbaMatchKey,
        station,
        createdAt: String(doc.createdAt),
        savedAt: now.toISOString(),
        qr: encodeQrScout(config, (doc.fieldValues ?? {}) as Values),
      };
      await props.persist(doc, entry);
      draftStore.clear();
      setError(null);
      setWarned(false);
      setDone(entry);
    } catch {
      setError(
        "Could not save the entry. Nothing was recorded, so do not leave this screen.",
      );
    } finally {
      setSaving(false);
    }
  }

  const saveRef = useRef(save);
  saveRef.current = save;
  const canSave = !saving && !!author.uid && !done;
  const canSaveRef = useRef(canSave);
  canSaveRef.current = canSave;
  const live = !done;
  useEffect(() => {
    if (!live) return;
    const onKey = (e: KeyboardEvent) => {
      if (
        !(e.ctrlKey || e.metaKey) ||
        e.altKey ||
        e.key.toLowerCase() !== "s"
      ) {
        return;
      }
      e.preventDefault();
      if (canSaveRef.current) void saveRef.current();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [live]);

  function nextMatch() {
    setForm((f) => resetForNext(f, ctx));
    setSketch(emptySketch());
    setResetToken((t) => t + 1);
    setDone(null);
    setStep(0);
    window.scrollTo?.({ top: 0 });
  }

  const matchKeyNow = resolveMatchKey(typedMatch, schedule);
  const thisMatch = done
    ? done.matchRef
    : matchRefOf(matchKeyNow, props.eventKey, typedMatch);
  const savedHere = saved.filter((e) => e.matchRef === thisMatch);

  const sheet = qrFor && (
    <QrSheet
      entry={saved.find((e) => e.id === qrFor.id) ?? qrFor}
      delivery={
        <DeliveryLine
          delivery={props.deliveryOf(qrFor.id)}
          signedIn={author.uid !== null}
        />
      }
      onClose={closeQr}
    />
  );

  const header = (
    <header className="scout-head">
      <div className="match-line">
        <span className="match-num">
          Match {done ? done.matchNumber : typedMatch || "?"}
        </span>
        <span className="tag" data-alliance={alliance?.toLowerCase() ?? "none"}>
          <span className="sr-only">Station </span>
          {done ? done.station || "?" : station || "?"}
        </span>
        <span className="team-num">
          Team {(done ? done.team : team) > 0 ? (done ? done.team : team) : "?"}
        </span>
      </div>
      <p className="status-line secondary" aria-live="polite">
        <span>{props.eventKey || "No event"}</span>
        <span>{props.online ? "Online" : "Offline"}</span>
        {props.unsent.pending > 0 && <span>{props.unsent.pending} unsent</span>}
        {props.unsent.refused > 0 && (
          <span>{props.unsent.refused} refused</span>
        )}
        {props.onScan && (
          <button type="button" className="btn scan-btn" onClick={props.onScan}>
            Scan QR
          </button>
        )}
      </p>
      {!done && props.shifts && creditStation && (
        <CreditBar
          credit={credit}
          shifts={props.shifts}
          standInUntil={
            credit?.standIn ? (props.standIn?.untilMatch ?? null) : null
          }
          matchKnown={matchNumber !== null && props.onStandIn !== undefined}
          onPick={(who) => {
            if (matchNumber === null || !props.shifts) return;
            props.onStandIn?.(
              startStandIn({
                shifts: props.shifts,
                station: creditStation,
                match: matchNumber,
                eventKey: props.eventKey,
                who,
              }),
            );
          }}
          onClearStandIn={() => props.onStandIn?.(null)}
        />
      )}
      {!done && (
        <nav className="steps" aria-label="Steps">
          {[...sections.map((s) => s.name), "Review"].map((name, i) => (
            <button
              key={name}
              type="button"
              className="step-tab"
              aria-current={i === step ? "step" : undefined}
              onClick={() => goTo(i)}
            >
              {name}
            </button>
          ))}
        </nav>
      )}
    </header>
  );

  if (done) {
    return (
      <div className="scout">
        {header}
        <div className="scout-body saved-view">
          <Check />
          <h1>Team {done.team} saved</h1>
          <p>
            <DeliveryLine
              delivery={props.deliveryOf(done.id)}
              signedIn={author.uid !== null}
            />
          </p>
          <button
            type="button"
            className="btn big"
            onClick={() => setQrFor(done)}
          >
            Show QR
          </button>
          <SavedList
            entries={savedHere}
            deliveryOf={props.deliveryOf}
            signedIn={author.uid !== null}
            onShowQr={setQrFor}
            {...(props.remove ? { onDelete: props.remove } : {})}
          />
        </div>
        <footer className="scout-foot">
          <button type="button" className="btn primary big" onClick={nextMatch}>
            Next match
          </button>
        </footer>
        {sheet}
      </div>
    );
  }

  const section = sections[step];
  const hideStation = (f: ScoutField) =>
    props.stationLocked === true && f.code === stationCode;
  const visible =
    section?.fields.filter((f) => isVisible(f, values) && !hideStation(f)) ??
    [];
  const stationUnset = props.deviceStation === null;

  return (
    <div className="scout">
      {header}
      <div className="scout-body">
        {section ? (
          <section aria-labelledby="step-h">
            <h2 id="step-h" className="sr-only">
              {section.name}
            </h2>
            {step === 0 && stationUnset && (
              <p className="notice-soft">
                Pick your station once. This device remembers it.
              </p>
            )}
            {step === 0 && (
              <p className="secondary link-line">
                {eventLinkMessage(props.eventKey, schedule, typedMatch)}
              </p>
            )}
            {visible.length === 0 && (
              <p className="secondary">Nothing to fill in here.</p>
            )}
            {visible.map((field) => (
              <FieldRow
                key={field.code}
                field={field}
                values={values}
                schedule={schedule}
                resetToken={resetToken}
                onChange={change}
                onPatch={patch}
              />
            ))}
            {drawingOn && step === reviewStep - 1 && (
              <SketchEditor
                title="Report drawing"
                surface="Scouting drawing"
                value={sketch}
                phased
                onChange={setSketch}
              />
            )}
          </section>
        ) : (
          <section aria-labelledby="step-h">
            <h2 id="step-h">Review</h2>
            {empty.length > 0 && (
              <div className="notice" role="alert">
                <p>Required, still empty:</p>
                <ul className="plain">
                  {empty.map((f) => (
                    <li key={f.code}>
                      <button
                        type="button"
                        className="link-btn"
                        onClick={() => goTo(Math.max(0, stepOfField(f.code)))}
                      >
                        {f.title}
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}
            {sections.map((s) => (
              <div key={s.name} className="review-group">
                <h3>{s.name}</h3>
                <dl className="rows">
                  {s.fields
                    .filter(
                      (f) =>
                        isVisible(f, values) &&
                        f.type !== "actionTracker" &&
                        f.type !== "document",
                    )
                    .map((f) => (
                      <div key={f.code} className="review-row">
                        <dt>{f.title}</dt>
                        <dd>{answerText(f, values[f.code]) || "No answer"}</dd>
                      </div>
                    ))}
                </dl>
              </div>
            ))}
            {savedHere.length > 0 && (
              <SavedList
                entries={savedHere}
                deliveryOf={props.deliveryOf}
                signedIn={author.uid !== null}
                onShowQr={setQrFor}
                {...(props.remove ? { onDelete: props.remove } : {})}
              />
            )}
          </section>
        )}
      </div>
      <footer className="scout-foot">
        {props.pit && (
          <PitBar
            team={team}
            entries={props.pit.entries}
            config={props.pit.config}
          />
        )}
        {error && (
          <p className="notice" role="alert">
            {error}
          </p>
        )}
        <div className="foot-row">
          <button
            type="button"
            className="btn"
            disabled={step === 0}
            onClick={() => goTo(step - 1)}
          >
            Back
          </button>
          <button
            type="button"
            className="btn"
            disabled={step >= reviewStep}
            onClick={() => goTo(step + 1)}
          >
            Next
          </button>
          <button
            type="button"
            className="btn primary"
            disabled={saving || !author.uid}
            onClick={() => void save()}
          >
            {!author.uid
              ? "Sign in to save"
              : warned && empty.length > 0
                ? "Save anyway"
                : "Save"}
          </button>
        </div>
      </footer>
      {sheet}
    </div>
  );
}

export function FieldRow(props: {
  field: ScoutField;
  values: Record<string, unknown>;
  schedule: ScheduledMatch[];
  resetToken: number;
  onChange(code: string, value: unknown): void;
  onPatch(patch: Record<string, unknown>): void;
}) {
  const { field } = props;
  return (
    <div className="field">
      <div className="field-title">
        <span className="field-name">{field.title}</span>
        {field.required && <span className="req">Required</span>}
      </div>
      {field.description && <p className="secondary">{field.description}</p>}
      <FieldInput {...props} />
    </div>
  );
}

export function SavedList({
  entries,
  deliveryOf,
  signedIn,
  onShowQr,
  onDelete,
}: {
  entries: SavedEntry[];
  deliveryOf(entryId: string): Delivery | undefined;
  signedIn: boolean;
  onShowQr(entry: SavedEntry): void;
  onDelete?(entry: SavedEntry): Promise<void>;
}) {
  if (entries.length === 0) return null;
  return (
    <div className="saved-list">
      <h3>Saved this match</h3>
      <ul className="outbox">
        {entries.map((e) => (
          <li key={e.id}>
            <div className="saved-info">
              <span>
                Team {e.team}
                {e.station ? ` at ${e.station}` : ""}
              </span>
              <DeliveryLine delivery={deliveryOf(e.id)} signedIn={signedIn} />
            </div>
            <button
              type="button"
              className="btn"
              aria-label={`Show QR for team ${e.team}`}
              onClick={() => onShowQr(e)}
            >
              Show QR
            </button>
            {onDelete && (
              <DeleteButton
                what={`entry for team ${e.team}`}
                prompt={`Delete the entry for team ${e.team}? It is removed from the database too.`}
                onConfirm={() => onDelete(e)}
              />
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
