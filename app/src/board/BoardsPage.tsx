import { deleteDoc, doc } from "firebase/firestore";
import { type FormEvent, useCallback, useEffect, useState } from "react";
import { Link, useNavigate } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { useRoles } from "../auth/rolesContext";
import { useTbaEvent } from "../data/useTbaEvent";
import { db } from "../firebase/client";
import { dismissItem, getOutbox } from "../outbox/outbox";
import { useScoutData } from "../scout/ScoutData";
import { useOnline } from "../ui/useOnline";
import { bundled } from "./field";
import {
  boardTitle,
  localSessions,
  maxPracticeTeams,
  parseTeamList,
  practiceBoard,
  scheduledClash,
  scopeBoards,
  sharedTeams,
} from "./list";
import {
  deleteLocal,
  idKey,
  type LocalBoard,
  listLocal,
  saveLocal,
} from "./local";
import { type Session, sessionJson } from "./model";
import { useRemoteBoards } from "./remote";
import "./board.css";

const stamp = (ms: number) =>
  new Date(ms).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });

function NewBoard({ eventKey }: { eventKey: string }) {
  const auth = useAuth();
  const roles = useRoles();
  const tba = useTbaEvent();
  const navigate = useNavigate();
  const [number, setNumber] = useState("");
  const [alliance, setAlliance] = useState<"Red" | "Blue">("Red");
  const [name, setName] = useState("");
  const [teams, setTeams] = useState("");
  const [opponents, setOpponents] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const uid = auth.uid ?? "";

  const clash = (n: number) =>
    scheduledClash(
      eventKey,
      n,
      tba.matches.map((m) => m.key),
    );

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const n = Number(number.trim());
    if (!Number.isInteger(n) || n < 1 || n > 999) {
      setError("Enter a match number from 1 to 999.");
      return;
    }
    if (clash(n)) {
      setError(
        `Match ${n} is on the schedule. Its board is on the Plan tab of that match.`,
      );
      return;
    }
    const list = parseTeamList(teams);
    const other = parseTeamList(opponents);
    const bad = [...list.bad, ...other.bad];
    if (bad.length > 0) {
      setError(`Not a team number: ${bad.join(", ")}.`);
      return;
    }
    const both = sharedTeams(list.teams, other.teams);
    if (both.length > 0) {
      setError(`On both sides: ${both.join(", ")}.`);
      return;
    }
    if (uid === "") {
      setError("Sign in to make a board.");
      return;
    }
    setError("");
    setBusy(true);
    const id = crypto.randomUUID();
    const session = practiceBoard({
      id,
      matchNumber: n,
      alliance,
      name: name.slice(0, 100),
      teams: list.teams,
      opponents: other.teams,
      eventKey,
      fieldId: bundled.latest,
      author: {
        uid,
        displayName:
          (roles.status === "ready" ? roles.displayName : "") ||
          auth.displayName ||
          "",
      },
      nowMs: Date.now(),
    });
    try {
      await saveLocal(idKey(id), { doc: sessionJson(session), queuedMs: 0 });
      navigate(`/boards/${id}`);
    } catch {
      setError("Could not save the board on this device. Free some storage.");
      setBusy(false);
    }
  };

  const typed = Number(number.trim());
  const link = Number.isInteger(typed) && typed > 0 ? clash(typed) : null;

  return (
    <section className="boards-new" aria-labelledby="boards-new-h">
      <h2 id="boards-new-h">New board for a practice or custom match</h2>
      <form onSubmit={submit} className="boards-form">
        <label className="boards-field">
          <span className="label">Match number</span>
          <input
            className="input"
            inputMode="numeric"
            autoComplete="off"
            value={number}
            onChange={(e) => setNumber(e.target.value)}
          />
        </label>
        <label className="boards-field">
          <span className="label">Our alliance</span>
          <select
            className="input"
            value={alliance}
            onChange={(e) => setAlliance(e.target.value as "Red" | "Blue")}
          >
            <option value="Red">Red</option>
            <option value="Blue">Blue</option>
          </select>
        </label>
        <label className="boards-field">
          <span className="label">Name, optional</span>
          <input
            className="input"
            maxLength={100}
            autoComplete="off"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </label>
        <label className="boards-field">
          <span className="label">
            {`Our teams, optional, up to ${maxPracticeTeams}`}
          </span>
          <input
            className="input"
            inputMode="numeric"
            autoComplete="off"
            placeholder="1111, 2222, 3333"
            value={teams}
            onChange={(e) => setTeams(e.target.value)}
          />
        </label>
        <label className="boards-field">
          <span className="label">
            {`Opponent teams, optional, up to ${maxPracticeTeams}`}
          </span>
          <input
            className="input"
            inputMode="numeric"
            autoComplete="off"
            placeholder="4444, 5555, 6666"
            value={opponents}
            onChange={(e) => setOpponents(e.target.value)}
          />
        </label>
        {link && (
          <p className="secondary" role="status">
            Match {typed} is on the schedule.{" "}
            <Link to={`${link}?tab=plan`}>Open its board</Link>
          </p>
        )}
        {error !== "" && (
          <p className="notice" role="alert">
            {error}
          </p>
        )}
        <button type="submit" className="btn primary" disabled={busy}>
          Create board
        </button>
      </form>
    </section>
  );
}

function BoardRow({
  board,
  author,
  inDatabase,
  onDelete,
  busy,
  canDelete,
}: {
  board: Session;
  author: boolean;
  inDatabase: boolean | null;
  onDelete?: () => void;
  busy: boolean;
  canDelete: boolean;
}) {
  const [asking, setAsking] = useState(false);
  const title = boardTitle(board);
  return (
    <li className="boards-item">
      <div className="boards-main">
        <Link to={`/boards/${board.id}`} className="boards-title">
          {title}
        </Link>
        <p className="secondary">
          {[
            `Alliance ${board.alliance}`,
            stamp(board.updatedMs),
            author
              ? board.authorDisplayName !== ""
                ? `by ${board.authorDisplayName}`
                : "by a teammate"
              : "",
            inDatabase === false ? "Not in the database yet" : "",
            inDatabase === null && !author ? "Checking the database" : "",
          ]
            .filter((p) => p !== "")
            .join(", ")}
        </p>
      </div>
      {onDelete && !asking && (
        <button
          type="button"
          className="btn"
          disabled={busy || !canDelete}
          aria-label={`Delete ${title}`}
          onClick={() => setAsking(true)}
        >
          Delete
        </button>
      )}
      {onDelete && asking && (
        <div className="boards-confirm" role="alert">
          <p>{`Delete "${title}" and its drawings?`}</p>
          <div className="actions">
            <button
              type="button"
              className="btn"
              disabled={busy}
              onClick={() => {
                setAsking(false);
                onDelete();
              }}
            >
              Delete board
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => setAsking(false)}
            >
              Keep it
            </button>
          </div>
        </div>
      )}
    </li>
  );
}

export function Boards() {
  const { eventKey } = useScoutData();
  const online = useOnline();
  const remote = useRemoteBoards();
  const [local, setLocal] = useState<LocalBoard[] | null>(null);
  const [thisEventOnly, setThisEventOnly] = useState(eventKey !== "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const reload = useCallback(() => {
    listLocal().then(setLocal, () => setLocal([]));
  }, []);
  useEffect(reload, [reload]);

  const sessions = local ? localSessions(local, bundled.latest) : [];
  const scoped = scopeBoards({
    local: sessions.map((s) => s.session),
    remote: remote.boards,
    selectedEventKey: eventKey,
    thisEventOnly,
  });
  const remoteIds = new Set(remote.boards.map((b) => b.id));

  const remove = async (id: string) => {
    setBusy(true);
    setError("");
    try {
      for (const item of getOutbox()) {
        if (
          item.path === `strategyBoards/${id}` &&
          item.status !== "in-database"
        ) {
          dismissItem(item.id);
        }
      }
      if (remoteIds.has(id)) await deleteDoc(doc(db, "strategyBoards", id));
      for (const held of local ?? []) {
        if (String(held.record.doc.id ?? "") === id)
          await deleteLocal(held.key);
      }
      reload();
    } catch {
      setError(
        "Could not delete the board. Only its author or a strategy lead can delete it, and this needs a connection.",
      );
    } finally {
      setBusy(false);
    }
  };

  const empty = local !== null && scoped.mine.length + scoped.team.length === 0;

  return (
    <div className="boards">
      <header className="boards-head">
        <h1>Boards</h1>
        <p className="secondary">
          Strategy boards for every match, and for practice matches. A match on
          the schedule keeps its board on the Plan tab of that match.
        </p>
      </header>

      <NewBoard eventKey={eventKey} />

      {eventKey !== "" && (
        <button
          type="button"
          className="chip boards-scope"
          aria-pressed={thisEventOnly}
          onClick={() => setThisEventOnly((on) => !on)}
        >
          {`This event only (${eventKey})`}
        </button>
      )}

      {error !== "" && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      {!online && (
        <p className="notice-soft" role="status">
          Offline. This shows the boards this device holds. Deleting needs a
          connection.
        </p>
      )}
      {remote.failed && (
        <p className="notice" role="status">
          Could not read the team's boards. This list may be incomplete.
        </p>
      )}

      {local === null ? (
        <p className="secondary" role="status">
          Loading the boards on this device.
        </p>
      ) : (
        <>
          {scoped.mine.length > 0 && (
            <section aria-labelledby="boards-mine-h" className="boards-group">
              <h2 id="boards-mine-h">Boards on this device</h2>
              <ul className="plain boards-list">
                {scoped.mine.map((b) => (
                  <BoardRow
                    key={b.id}
                    board={b}
                    author={false}
                    inDatabase={remote.ready ? remoteIds.has(b.id) : null}
                    busy={busy}
                    canDelete={online && remote.ready}
                    onDelete={() => remove(b.id)}
                  />
                ))}
              </ul>
            </section>
          )}
          {scoped.team.length > 0 && (
            <section aria-labelledby="boards-team-h" className="boards-group">
              <h2 id="boards-team-h">Team boards</h2>
              <p className="secondary">
                Drawn by teammates. Open one to copy it to this device.
              </p>
              <ul className="plain boards-list">
                {scoped.team.map((b) => (
                  <BoardRow
                    key={b.id}
                    board={b}
                    author
                    inDatabase={null}
                    busy={busy}
                    canDelete={false}
                  />
                ))}
              </ul>
            </section>
          )}
          {!remote.ready && (
            <p className="secondary" role="status">
              Loading the team's boards.
            </p>
          )}
          {empty && remote.ready && (
            <p className="secondary" role="status">
              {scoped.hidden > 0
                ? `No boards for this event yet. ${scoped.hidden} from other events ${scoped.hidden === 1 ? "is" : "are"} hidden.`
                : "No boards yet."}
            </p>
          )}
        </>
      )}
    </div>
  );
}
