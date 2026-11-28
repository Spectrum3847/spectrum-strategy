import { useState } from "react";
import { Link, useSearchParams } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { FormsPanel } from "../configEditor/FormsPanel";
import { ExportPanel } from "../export/ExportPanel";
import { myTeamStore, parseTeamNumber, useMyTeam } from "../now/myTeam";
import {
  deleteProofEntries,
  dismissFinished,
  dismissItem,
  enqueueProofEntry,
} from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { PushPanel } from "../push/PushPanel";
import { ReportProblem } from "../reports/ReportProblem";
import {
  lockedStationStore,
  standInStore,
  useLockedStation,
} from "../scout/local";
import { useScoutData } from "../scout/ScoutData";
import { About } from "../settings/About";
import { ClearCachePanel } from "../settings/ClearCachePanel";
import { EventPanel } from "../settings/EventPanel";
import { type Section, sectionFor, sections } from "../settings/sections";
import { TourPanel } from "../tour/TourPanel";
import { SharePanel } from "../usage/SharePanel";
import "../settings/settings.css";
import { applyTheme, getTheme, type ThemeChoice } from "../theme";
import { useTrainingSession } from "../training/session";
import { TrainingPanel } from "../training/TrainingPanel";

const statusText = {
  "on-device": "On this device",
  sending: "Sending",
  "in-database": "In the database",
  refused: "Refused",
} as const;

const proofEnabled =
  import.meta.env.DEV || import.meta.env.VITE_OUTBOX_PROOF === "true";

function SignInPanel() {
  const auth = useAuth();
  return (
    <section className="panel" aria-labelledby="signin-h">
      <h2 id="signin-h">Sign-in</h2>
      <dl className="rows">
        <dt>State</dt>
        <dd>{auth.status}</dd>
        {auth.uid && (
          <>
            <dt>User</dt>
            <dd>{auth.displayName ?? auth.uid}</dd>
          </>
        )}
      </dl>
      {auth.error && (
        <p className="notice" role="alert">
          {auth.error}
        </p>
      )}
      <div className="actions">
        {auth.status === "signed-in" ? (
          <button type="button" className="btn" onClick={auth.signOut}>
            Sign out
          </button>
        ) : (
          <button
            type="button"
            className="btn primary"
            disabled={auth.status !== "signed-out"}
            onClick={auth.signIn}
          >
            {auth.status === "signing-in"
              ? "Signing in"
              : "Sign in with Google"}
          </button>
        )}
      </div>
    </section>
  );
}

function OutboxPanel() {
  const auth = useAuth();
  const items = useOutbox();
  const signedIn = auth.status === "signed-in";
  const finished = items.some((i) => i.status === "in-database");
  return (
    <section className="panel" aria-labelledby="outbox-h">
      <h2 id="outbox-h">Outbox</h2>
      {items.length === 0 ? (
        <p className="secondary">Nothing waiting.</p>
      ) : (
        <ul className="outbox">
          {items.map((item) => (
            <li key={item.id}>
              <span>{item.label}</span>
              <span className="state" data-state={item.status}>
                {!signedIn &&
                (item.status === "on-device" || item.status === "sending")
                  ? "Waiting for sign-in"
                  : statusText[item.status]}
              </span>
              {item.error && <span className="secondary">{item.error}</span>}
              {item.status === "refused" && (
                <span>
                  <button
                    type="button"
                    className="btn"
                    onClick={() => dismissItem(item.id)}
                  >
                    Dismiss
                  </button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
      <div className="actions">
        {proofEnabled && (
          <button
            type="button"
            className="btn primary"
            disabled={auth.status !== "signed-in" || !auth.uid}
            onClick={() =>
              auth.uid &&
              enqueueProofEntry(auth.uid, auth.displayName ?? "Proof")
            }
          >
            Write proof entry
          </button>
        )}
        {proofEnabled && (
          <button
            type="button"
            className="btn"
            disabled={!signedIn || !auth.uid}
            onClick={() => auth.uid && void deleteProofEntries(auth.uid)}
          >
            Delete proof entries
          </button>
        )}
        {finished && (
          <button type="button" className="btn" onClick={dismissFinished}>
            Clear finished
          </button>
        )}
      </div>
    </section>
  );
}

function TeamPanel() {
  const team = useMyTeam();
  const [draft, setDraft] = useState(team === null ? "" : String(team));
  const parsed = parseTeamNumber(draft);
  return (
    <section className="panel" aria-labelledby="team-h">
      <h2 id="team-h">Our team</h2>
      <p className="secondary">
        Now uses this to find your next match. It stays on this device.
      </p>
      <form
        className="actions"
        onSubmit={(e) => {
          e.preventDefault();
          if (parsed !== null) myTeamStore.set(parsed);
        }}
      >
        <input
          className="input"
          aria-label="Team number"
          inputMode="numeric"
          placeholder="3847"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
        />
        <button
          type="submit"
          className="btn"
          disabled={parsed === null || parsed === team}
        >
          Save
        </button>
        <button
          type="button"
          className="btn"
          disabled={team === null}
          onClick={() => {
            myTeamStore.set(null);
            setDraft("");
          }}
        >
          Clear
        </button>
      </form>
      <dl className="rows">
        <dt>Team</dt>
        <dd>{team ?? "Not set"}</dd>
      </dl>
    </section>
  );
}

const stationChoices = ["R1", "R2", "R3", "B1", "B2", "B3"] as const;

function StationPanel() {
  const locked = useLockedStation();
  const roles = useRoles();
  const canChange = roles.status === "ready" && isLead(roles.roles);
  const pick = (station: string | null) => {
    lockedStationStore.set(station);
    standInStore.set(null);
  };
  return (
    <section className="panel" aria-labelledby="station-h">
      <h2 id="station-h">This iPad's station</h2>
      <p className="secondary">
        A lead sets this once for a shared station iPad. The Scout form stops
        asking for a station, and each entry is credited to the scout the shift
        schedule puts there.
      </p>
      {!canChange && (
        <p className="secondary">
          {locked
            ? `Locked to ${locked}. Only a strategy lead can change it.`
            : "Not locked. A strategy lead can lock this iPad to a station."}
        </p>
      )}
      <div className="station-grid">
        {stationChoices.map((station) => (
          <button
            key={station}
            type="button"
            className={station === locked ? "btn primary" : "btn"}
            aria-pressed={station === locked}
            disabled={!canChange}
            onClick={() => pick(station)}
          >
            {station}
          </button>
        ))}
      </div>
      <div className="actions">
        <button
          type="button"
          className="btn"
          disabled={!canChange || locked === null}
          onClick={() => pick(null)}
        >
          Not locked
        </button>
      </div>
    </section>
  );
}

function ThemePanel() {
  const [theme, setTheme] = useState<ThemeChoice>(getTheme);
  return (
    <section className="panel" aria-labelledby="theme-h">
      <h2 id="theme-h">Theme</h2>
      <div className="actions">
        {(["auto", "light", "dark"] as const).map((choice) => (
          <button
            key={choice}
            type="button"
            className={choice === theme ? "btn primary" : "btn"}
            aria-pressed={choice === theme}
            onClick={() => {
              setTheme(choice);
              applyTheme(choice);
            }}
          >
            {choice[0]?.toUpperCase()}
            {choice.slice(1)}
          </button>
        ))}
      </div>
    </section>
  );
}

function Chevron() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="20"
      height="20"
      aria-hidden="true"
      focusable="false"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}

function ManualsPanel() {
  return (
    <section className="panel" aria-labelledby="manuals-h">
      <h2 id="manuals-h">Manuals</h2>
      <p className="secondary">
        The team manuals for your role, readable offline.
      </p>
      <div className="actions">
        <Link className="btn" to="/help">
          Open the manuals
        </Link>
      </div>
    </section>
  );
}

function SectionList() {
  const auth = useAuth();
  const { eventKey } = useScoutData();
  const waiting = useOutbox().filter((i) => i.status !== "in-database").length;
  const values: Record<string, string> = {
    event: eventKey || "No event",
    data: waiting > 0 ? `${waiting} waiting` : "",
    account: auth.status === "signed-in" ? "Signed in" : "Signed out",
  };
  return (
    <>
      <h1>Settings</h1>
      <ul className="plain settings-list">
        {sections.map((section) => (
          <li key={section.id}>
            <Link to={`?s=${section.id}`}>
              <span className="settings-item-text">
                <span className="settings-item-title">{section.title}</span>
                <span className="secondary">{section.detail}</span>
              </span>
              <span className="settings-item-value">{values[section.id]}</span>
              <Chevron />
            </Link>
          </li>
        ))}
      </ul>
    </>
  );
}

function SectionBody({ id }: { id: Section["id"] }) {
  const training = useTrainingSession() !== null;
  switch (id) {
    case "event":
      return (
        <>
          {training ? null : <EventPanel />}
          <TrainingPanel />
        </>
      );
    case "device":
      return (
        <>
          <TeamPanel />
          <StationPanel />
          <ThemePanel />
          <PushPanel />
          <SharePanel />
          <ClearCachePanel />
        </>
      );
    case "data":
      return (
        <>
          <OutboxPanel />
          <ExportPanel />
        </>
      );
    case "forms":
      return <FormsPanel />;
    case "account":
      return <SignInPanel />;
    case "help":
      return (
        <>
          <ManualsPanel />
          <TourPanel />
          <ReportProblem />
          <About />
        </>
      );
  }
}

export function Settings() {
  const [params] = useSearchParams();
  const section = sectionFor(params.get("s"));
  return (
    <div className="settings">
      {section ? (
        <>
          <Link className="settings-back" to="/settings">
            <Chevron />
            Settings
          </Link>
          <h1>{section.title}</h1>
          <SectionBody id={section.id} />
        </>
      ) : (
        <SectionList />
      )}
    </div>
  );
}
