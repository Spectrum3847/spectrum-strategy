import { useRef, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { canWrite } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { enqueueWrite } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { preparePhoto } from "../photos/compress";
import { uploadPhoto } from "../photos/service";
import { DeliveryLine } from "../scout/ScoutForm";
import { isTraining, TrainingWriteError } from "../training/session";
import {
  areas,
  bugReportDoc,
  type Environment,
  environment,
  impacts,
  type Kind,
  kindLabels,
  kinds,
  maxBody,
  maxScreenshots,
  maxTitle,
} from "./bugReport";
import "./reports.css";
import { uploadScreenshots } from "./screenshots";

function currentEnvironment(): Environment {
  return environment(
    { version: __APP_VERSION__, sha: __BUILD_SHA__, time: __BUILD_TIME__ },
    {
      userAgent: navigator.userAgent,
      maxTouchPoints: navigator.maxTouchPoints,
      standalone:
        window.matchMedia?.("(display-mode: standalone)").matches === true,
    },
  );
}

export function ReportProblem() {
  const auth = useAuth();
  const roles = useRoles();
  const outbox = useOutbox();
  const [kind, setKind] = useState<Kind>("bug");
  const [area, setArea] = useState("");
  const [impact, setImpact] = useState("");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [screenshots, setScreenshots] = useState<{ id: string; file: File }[]>(
    [],
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentId, setSentId] = useState<string | null>(null);
  const [dropped, setDropped] = useState(0);
  const picker = useRef<HTMLInputElement>(null);

  if (roles.status !== "ready" || !canWrite(roles.roles)) return null;

  const uid = auth.status === "signed-in" ? auth.uid : null;
  const env = currentEnvironment();
  const sent = outbox.find((i) => i.id === sentId);
  const ready = title.trim() !== "";

  const pick = (input: HTMLInputElement) => {
    const chosen = [...(input.files ?? [])].map((file) => ({
      id: crypto.randomUUID(),
      file,
    }));
    input.value = "";
    setScreenshots((now) => [...now, ...chosen].slice(0, maxScreenshots));
  };

  const send = async () => {
    if (uid === null) return;
    setBusy(true);
    setError(null);
    setDropped(0);
    try {
      if (isTraining()) throw new TrainingWriteError();
      const shots = await uploadScreenshots(
        screenshots.map((s) => s.file),
        {
          prepare: preparePhoto,
          upload: uploadPhoto,
        },
      );
      const id = crypto.randomUUID();
      const doc = bugReportDoc(
        { kind, area, impact, title, body, screenshotKeys: shots.keys },
        {
          uid,
          name: roles.displayName || auth.displayName || "",
          roles: roles.roles,
        },
        env,
        id,
        new Date(),
      );
      setSentId(await enqueueWrite(`bugReports/${id}`, doc, "Problem report"));
      setDropped(shots.dropped);
      setTitle("");
      setBody("");
      setScreenshots([]);
    } catch (e) {
      setError(
        e instanceof TrainingWriteError
          ? e.message
          : "Could not save on this device. Try again.",
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="panel" aria-labelledby="report-problem-h">
      <h2 id="report-problem-h">Report a problem</h2>
      <p className="secondary report-attached">
        Attached for the team: your name and roles, app version {env.appVersion}
        {env.osVersion !== "" && `, ${env.osVersion}`}, {env.deviceInfo}.
      </p>
      <form
        className="report-form"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <fieldset className="chips report-kind">
          <legend className="sr-only">Kind of report</legend>
          {kinds.map((k) => (
            <button
              key={k}
              type="button"
              className="chip"
              aria-pressed={k === kind}
              onClick={() => setKind(k)}
            >
              {kindLabels[k]}
            </button>
          ))}
        </fieldset>
        <label className="report-field">
          <span className="field-name">Area</span>
          <select
            className="input"
            value={area}
            onChange={(e) => setArea(e.target.value)}
          >
            <option value="">Not set</option>
            {areas.map((a) => (
              <option key={a} value={a}>
                {a}
              </option>
            ))}
          </select>
        </label>
        {kind === "bug" && (
          <label className="report-field">
            <span className="field-name">Impact</span>
            <select
              className="input"
              value={impact}
              onChange={(e) => setImpact(e.target.value)}
            >
              <option value="">Not set</option>
              {impacts.map((i) => (
                <option key={i} value={i}>
                  {i}
                </option>
              ))}
            </select>
          </label>
        )}
        <label className="report-field">
          <span className="field-name">Summary</span>
          <input
            className="input"
            maxLength={maxTitle}
            placeholder="Board did not save my drawing"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </label>
        <label className="report-field">
          <span className="field-name">
            {kind === "feedback" ? "Your feedback" : "What happened"}
          </span>
          <textarea
            className="input"
            rows={5}
            maxLength={maxBody}
            placeholder={
              kind === "feedback"
                ? "What would you like to see?"
                : "Steps to reproduce, what you expected, and so on."
            }
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
        </label>
        <div className="report-field">
          <span className="field-name">Screenshots</span>
          <p className="secondary">
            Up to {maxScreenshots}. They upload when you tap Send, so you need a
            connection. If a screenshot fails to upload, the report is still
            sent without it.
          </p>
          {screenshots.length > 0 && (
            <ul className="plain report-shots">
              {screenshots.map(({ id, file }) => (
                <li key={id}>
                  <span>{file.name}</span>
                  <button
                    type="button"
                    className="btn"
                    aria-label={`Remove ${file.name}`}
                    onClick={() =>
                      setScreenshots(screenshots.filter((s) => s.id !== id))
                    }
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
          <div className="actions">
            <button
              type="button"
              className="btn"
              disabled={busy || screenshots.length >= maxScreenshots}
              onClick={() => picker.current?.click()}
            >
              Add screenshot
            </button>
          </div>
          <input
            ref={picker}
            type="file"
            accept="image/*"
            multiple
            hidden
            onChange={(e) => pick(e.currentTarget)}
          />
        </div>
        <div className="actions">
          <button
            type="submit"
            className="btn primary"
            disabled={!ready || busy || uid === null}
          >
            {busy ? "Sending" : "Send report"}
          </button>
          {(sent || error) && (
            <span role="status">
              {error ? (
                <span className="state" data-state="refused">
                  {error}
                </span>
              ) : (
                <DeliveryLine
                  delivery={
                    sent
                      ? {
                          status: sent.status,
                          ...(sent.error ? { error: sent.error } : {}),
                        }
                      : undefined
                  }
                  signedIn={uid !== null}
                />
              )}
            </span>
          )}
        </div>
        {dropped > 0 && (
          <p className="notice" role="status">
            {dropped === 1
              ? "1 screenshot could not be attached."
              : `${dropped} screenshots could not be attached.`}{" "}
            The report was sent without {dropped === 1 ? "it" : "them"}.
          </p>
        )}
        {uid === null && <p className="secondary">Sign in to send a report.</p>}
      </form>
    </section>
  );
}
