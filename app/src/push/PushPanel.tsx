import { useCallback, useEffect, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { getOutbox, subscribeOutbox } from "../outbox/outbox";
import { whenInDatabase } from "../outbox/settled";
import { useOutbox } from "../outbox/useOutbox";
import { useTrainingSession } from "../training/session";
import { useOnline } from "../ui/useOnline";
import {
  type PushStatus,
  readStatus,
  sendTest,
  turnOff,
  turnOn,
} from "./client";
import type { PushState } from "./state";
import { subscriptionPath } from "./subscription";
import "./push.css";

type Busy = "on" | "off" | "test" | null;
interface Message {
  ok: boolean;
  text: string;
}

const stateText: Record<PushState, string> = {
  unsupported: "Not supported",
  "needs-home-screen": "Needs the Home Screen app",
  denied: "Blocked",
  off: "Off",
  on: "On",
};

const savedText = {
  "on-device": "Waiting to send",
  sending: "Sending",
  "in-database": "In the database",
  refused: "Refused",
} as const;

function Steps() {
  return (
    <div className="notice-soft">
      <p>On iPhone and iPad, reminders need the app on your Home Screen.</p>
      <ol className="push-steps">
        <li>Open this page in Safari.</li>
        <li>Tap Share, then Add to Home Screen.</li>
        <li>Open Strategy from the Home Screen and come back to Settings.</li>
      </ol>
    </div>
  );
}

function Guidance({ state }: { state: PushState }) {
  switch (state) {
    case "needs-home-screen":
      return <Steps />;
    case "unsupported":
      return (
        <p className="notice-soft">
          This browser cannot receive push notifications. Use a current Chrome,
          Edge, Firefox or Safari.
        </p>
      );
    case "denied":
      return (
        <p className="notice-soft">
          Notifications are blocked for this app. Allow them in your browser or
          device settings, then come back here.
        </p>
      );
    default:
      return null;
  }
}

export function PushPanel() {
  const auth = useAuth();
  const online = useOnline();
  const outbox = useOutbox();
  const training = useTrainingSession() !== null;
  const [status, setStatus] = useState<PushStatus | null>(null);
  const [busy, setBusy] = useState<Busy>(null);
  const [message, setMessage] = useState<Message | null>(null);

  const refresh = useCallback(async () => setStatus(await readStatus()), []);
  useEffect(() => {
    void refresh();
    const onShow = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    window.addEventListener("focus", onShow);
    document.addEventListener("visibilitychange", onShow);
    return () => {
      window.removeEventListener("focus", onShow);
      document.removeEventListener("visibilitychange", onShow);
    };
  }, [refresh]);

  const run = async (
    which: Exclude<Busy, null>,
    action: () => Promise<Message | null>,
  ) => {
    setBusy(which);
    setMessage(null);
    try {
      setMessage(await action());
    } catch (error) {
      setMessage({
        ok: false,
        text: error instanceof Error ? error.message : "Something went wrong.",
      });
    }
    await refresh();
    setBusy(null);
  };

  const signedIn = auth.status === "signed-in" && auth.uid !== null;
  const state = status?.state;
  const saved = status?.id
    ? outbox.find((item) => item.path === subscriptionPath(status.id ?? ""))
    : undefined;

  return (
    <section className="panel" aria-labelledby="push-h">
      <h2 id="push-h">Shift reminders</h2>
      <p className="secondary">
        A notification 3 matches before each of your scouting shifts, even when
        the app is closed. Slack messages keep coming as a backup.
      </p>
      <dl className="rows">
        <dt>State</dt>
        <dd>{state ? stateText[state] : "Checking"}</dd>
        {state === "on" && saved && (
          <>
            <dt>Saved</dt>
            <dd>
              {savedText[saved.status]}
              {saved.error ? `: ${saved.error}` : ""}
            </dd>
          </>
        )}
      </dl>
      {state && <Guidance state={state} />}
      {state === "off" && !signedIn && (
        <p className="secondary">Sign in to turn reminders on.</p>
      )}
      {state === "off" && training && (
        <p className="secondary">Not available in training mode.</p>
      )}
      {(state === "off" || state === "on") && !online && (
        <p className="secondary">Needs a connection to set up or test.</p>
      )}
      {message && (
        <p
          className={message.ok ? "notice-soft" : "notice"}
          role={message.ok ? "status" : "alert"}
        >
          {message.text}
        </p>
      )}
      <div className="actions">
        {state === "off" && (
          <button
            type="button"
            className="btn primary"
            disabled={busy !== null || !signedIn || !online || training}
            onClick={() =>
              auth.uid &&
              run("on", async () => {
                const result = await turnOn(auth.uid ?? "");
                return result.ok
                  ? { ok: true, text: "Reminders are on for this device." }
                  : { ok: false, text: result.message };
              })
            }
          >
            {busy === "on" ? "Turning on" : "Turn on reminders"}
          </button>
        )}
        {state === "on" && (
          <>
            <button
              type="button"
              className="btn"
              disabled={busy !== null || !online}
              onClick={() =>
                run("test", async () => {
                  if (saved && saved.status !== "in-database") {
                    const stored = await Promise.race([
                      whenInDatabase(saved.path, getOutbox, subscribeOutbox),
                      new Promise<boolean>((done) =>
                        setTimeout(() => done(false), 15_000),
                      ),
                    ]);
                    if (!stored) {
                      return {
                        ok: false,
                        text: "This device's reminder setup has not reached the database yet. Check the connection, then try again.",
                      };
                    }
                  }
                  const answer = await sendTest();
                  return { ok: answer.ok, text: answer.text };
                })
              }
            >
              {busy === "test" ? "Sending" : "Send a test"}
            </button>
            <button
              type="button"
              className="btn"
              disabled={busy !== null}
              onClick={() =>
                run("off", async () => {
                  await turnOff();
                  return {
                    ok: true,
                    text: "Reminders are off for this device.",
                  };
                })
              }
            >
              {busy === "off" ? "Turning off" : "Turn off"}
            </button>
          </>
        )}
      </div>
    </section>
  );
}
