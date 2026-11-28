import { type FormEvent, useId, useMemo, useState } from "react";
import { allRoles, type Role } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { dismissItem, type OutboxItem } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { useOnline } from "../ui/useOnline";
import {
  linkCandidates,
  linkWrites,
  maxNameLength,
  type ProfileWrite,
  profilePath,
  renameWrite,
  rolesWrites,
  unlinkWrites,
} from "./edits";
import {
  isLinkedSecondary,
  type ManagedProfile,
  matchesSearch,
  normalizeRoles,
  roleLabel,
  rolesText,
  usersView,
} from "./profiles";
import { saveProfileWrites, useProfiles } from "./useProfiles";
import "./users.css";

const statusText = {
  "on-device": "On this device",
  sending: "Sending",
  "in-database": "In the database",
  refused: "Refused",
} as const;

function Delivery({ item }: { item: OutboxItem | undefined }) {
  if (!item) return null;
  const finished = item.status === "in-database" || item.status === "refused";
  return (
    <p className="user-delivery">
      <span className="state" data-state={item.status}>
        {item.label}: {statusText[item.status]}
      </span>
      {item.status === "refused" && item.error && (
        <span className="secondary">{item.error}</span>
      )}
      {finished && (
        <button
          type="button"
          className="link-btn"
          onClick={() => dismissItem(item.id)}
        >
          Dismiss
        </button>
      )}
    </p>
  );
}

interface EditorProps {
  profile: ManagedProfile;
  roster: ManagedProfile[];
  ownUid: string;
  run(writes: ProfileWrite[]): Promise<void>;
  close(): void;
}

function Editor({ profile, roster, ownUid, run, close }: EditorProps) {
  const id = useId();
  const [name, setName] = useState(profile.displayName);
  const [picked, setPicked] = useState<Set<Role>>(new Set(profile.roles));
  const [primaryUid, setPrimaryUid] = useState("");
  const [busy, setBusy] = useState(false);

  const act = async (build: () => ProfileWrite[]) => {
    setBusy(true);
    try {
      await run(build());
    } finally {
      setBusy(false);
    }
  };

  const toggle = (role: Role, on: boolean) =>
    setPicked((p) => {
      const next = new Set(p);
      if (on) next.add(role);
      else next.delete(role);
      return next;
    });

  const saveName = (e: FormEvent) => {
    e.preventDefault();
    void act(() => [renameWrite(profile, name, ownUid)]);
  };
  const saveRoles = (e: FormEvent) => {
    e.preventDefault();
    void act(() => rolesWrites(profile, picked, roster, ownUid));
  };

  const primary = profile.canonicalUid
    ? (roster.find((p) => p.uid === profile.canonicalUid) ?? null)
    : null;
  const candidates = linkCandidates(profile, roster, ownUid);
  const chosen = candidates.find((p) => p.uid === primaryUid);
  const nameChanged = name.trim() !== "" && name.trim() !== profile.displayName;
  const rolesChanged =
    normalizeRoles(picked).join() !== normalizeRoles(profile.roles).join();
  const linkedToOwn = profile.canonicalUid === ownUid;

  return (
    <div className="user-editor" id={`${id}-editor`}>
      <form className="user-section" onSubmit={saveName}>
        <label className="field-name" htmlFor={`${id}-name`}>
          Display name
        </label>
        <p className="secondary">
          The name on everything this account submits. It reaches their device
          on their next sign-in.
        </p>
        <div className="actions">
          <input
            id={`${id}-name`}
            className="input"
            value={name}
            maxLength={maxNameLength}
            autoComplete="off"
            onChange={(e) => setName(e.target.value)}
          />
          <button type="submit" className="btn" disabled={busy || !nameChanged}>
            Save name
          </button>
        </div>
      </form>

      <form className="user-section" onSubmit={saveRoles}>
        <fieldset className="user-roles">
          <legend className="field-name">Roles</legend>
          <p className="secondary">
            Applies to every account linked to this person.
          </p>
          {allRoles.map((role) => (
            <label key={role} className="user-check">
              <input
                type="checkbox"
                checked={picked.has(role)}
                onChange={(e) => toggle(role, e.target.checked)}
              />
              {roleLabel[role]}
            </label>
          ))}
          {picked.size === 0 && (
            <p className="secondary">No role selected saves as Viewer.</p>
          )}
        </fieldset>
        <div className="actions">
          <button
            type="submit"
            className="btn primary"
            disabled={busy || !rolesChanged}
          >
            Save roles
          </button>
        </div>
      </form>

      <div className="user-section">
        <h4 className="field-name">Linked account</h4>
        {isLinkedSecondary(profile) ? (
          <>
            <p className="secondary">
              Linked to{" "}
              {primary
                ? primary.displayName || primary.email
                : profile.canonicalUid}
              . Unlinking sets this account back to Viewer.
            </p>
            {linkedToOwn && (
              <p className="secondary">
                It is linked to your own profile, which you cannot edit.
              </p>
            )}
            <div className="actions">
              <button
                type="button"
                className="btn"
                disabled={busy || linkedToOwn}
                onClick={() =>
                  void act(() => unlinkWrites(profile, primary, ownUid))
                }
              >
                Unlink
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="secondary">
              The account keeps its own sign-in, but submits under the name and
              roles of the one you pick.
            </p>
            {!profile.email && (
              <p className="secondary">
                This account has no email address, so it cannot be linked.
              </p>
            )}
            <div className="actions">
              <select
                className="input"
                aria-label="Link to account"
                value={primaryUid}
                onChange={(e) => setPrimaryUid(e.target.value)}
              >
                <option value="">Pick an account</option>
                {candidates.map((p) => (
                  <option key={p.uid} value={p.uid}>
                    {p.displayName || "(no name)"} ({p.email ?? p.uid})
                  </option>
                ))}
              </select>
              <button
                type="button"
                className="btn"
                disabled={busy || !chosen || !profile.email}
                onClick={() =>
                  chosen && void act(() => linkWrites(profile, chosen, ownUid))
                }
              >
                Link
              </button>
            </div>
          </>
        )}
      </div>

      <div className="actions">
        <button type="button" className="btn" onClick={close}>
          Close
        </button>
      </div>
    </div>
  );
}

function Row({
  profile,
  roster,
  ownUid,
  item,
  open,
  setOpen,
  run,
}: {
  profile: ManagedProfile;
  roster: ManagedProfile[];
  ownUid: string;
  item: OutboxItem | undefined;
  open: boolean;
  setOpen(open: boolean): void;
  run(writes: ProfileWrite[]): Promise<void>;
}) {
  const own = profile.uid === ownUid;
  const primary = roster.find((p) => p.uid === profile.canonicalUid);
  return (
    <li className="user">
      <div className="user-main">
        <h3 className="user-name">{profile.displayName || "(no name)"}</h3>
        {profile.email && <p className="secondary">{profile.email}</p>}
        <p className="secondary">Roles: {rolesText(profile.roles)}</p>
        {isLinkedSecondary(profile) && (
          <p className="secondary">
            Linked to {primary?.displayName || profile.canonicalUid}
          </p>
        )}
        {profile.linkedEmails.length > 0 && (
          <p className="secondary">
            Also signs in as: {profile.linkedEmails.join(", ")}
          </p>
        )}
        {own && <p className="secondary">You cannot edit your own profile.</p>}
        <Delivery item={item} />
      </div>
      {!own && (
        <button
          type="button"
          className="btn"
          aria-expanded={open}
          aria-label={`${open ? "Close editor for" : "Edit"} ${profile.displayName || profile.email || profile.uid}`}
          onClick={() => setOpen(!open)}
        >
          {open ? "Close" : "Edit"}
        </button>
      )}
      {open && !own && (
        <Editor
          profile={profile}
          roster={roster}
          ownUid={ownUid}
          run={run}
          close={() => setOpen(false)}
        />
      )}
    </li>
  );
}

export function Users() {
  const roles = useRoles();
  const online = useOnline();
  const outbox = useOutbox();
  const [attempt, setAttempt] = useState(0);
  const [search, setSearch] = useState("");
  const [openUid, setOpenUid] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const searchId = useId();
  const seen = useProfiles(attempt);
  const view = usersView(seen);
  const ownUid = roles.status === "ready" ? roles.uid : "";

  const shown = useMemo(
    () => seen.items.filter((p) => matchesSearch(p, search)),
    [seen.items, search],
  );

  const run = async (writes: ProfileWrite[]) => {
    setError(null);
    try {
      await saveProfileWrites(writes);
      setOpenUid(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "The change was not saved.");
    }
  };

  const retry = () => setAttempt((n) => n + 1);

  return (
    <div className="users">
      <h1>Users</h1>
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      {view.kind === "loading" && (
        <p className="secondary" role="status">
          Loading users.
        </p>
      )}
      {view.kind === "refused" && (
        <div className="notice" role="alert">
          <p>
            The database refused the user list. Only admin accounts can manage
            users.
          </p>
          <button type="button" className="btn" onClick={retry}>
            Try again
          </button>
        </div>
      )}
      {view.kind === "failed" && (
        <div className="notice" role="alert">
          <p>Could not load users.</p>
          <button type="button" className="btn" onClick={retry}>
            Try again
          </button>
        </div>
      )}
      {view.kind === "nothing-cached" && (
        <div className="notice-soft" role="status">
          <p>
            {online
              ? "Waiting for the database. This device has no saved user list yet."
              : "You are offline and this device has no saved user list. Connect once to load it."}
          </p>
        </div>
      )}
      {view.kind === "empty" && (
        <p className="secondary" role="status">
          No users found.
        </p>
      )}
      {view.kind === "list" && (
        <>
          {view.source === "cache" && (
            <p className="notice-soft" role="status">
              {online
                ? "Waiting for the database. This list is the copy saved on this device."
                : "You are offline. This list is the copy saved on this device, and changes wait to send until you reconnect."}
            </p>
          )}
          <div className="user-search">
            <label className="field-name" htmlFor={searchId}>
              Search by name or email
            </label>
            <input
              id={searchId}
              type="search"
              className="input"
              value={search}
              autoComplete="off"
              onChange={(e) => setSearch(e.target.value)}
            />
            <p className="secondary" aria-live="polite">
              {shown.length === seen.items.length
                ? `${seen.items.length} users`
                : `${shown.length} of ${seen.items.length} users`}
            </p>
          </div>
          {shown.length === 0 ? (
            <p className="secondary">No user matches that search.</p>
          ) : (
            <ul className="users-list">
              {shown.map((p) => (
                <Row
                  key={p.uid}
                  profile={p}
                  roster={seen.items}
                  ownUid={ownUid}
                  item={outbox.find((i) => i.path === profilePath(p.uid))}
                  open={openUid === p.uid}
                  setOpen={(open) => setOpenUid(open ? p.uid : null)}
                  run={run}
                />
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}
