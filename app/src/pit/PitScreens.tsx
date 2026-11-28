import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { readCache } from "../data/cache";
import type { PitEntry } from "../data/parse";
import { useFormConfig, usePitEntries } from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { startValues } from "../forms/config";
import { deleteFormEntry, useCanDelete } from "../forms/deleteEntry";
import {
  deliveryAt,
  persistForm,
  persistMerge,
  unsentCount,
} from "../forms/delivery";
import { formEntryDocument, pitAnswersMerge } from "../forms/document";
import { EntryForm } from "../forms/EntryForm";
import { ownPitEntry, pitEntriesFor, pitRows } from "../forms/entries";
import { useIsLead, useSettled } from "../forms/hooks";
import { parseTeamParam } from "../forms/kinds";
import {
  FilterChips,
  ListHead,
  OpenTeam,
  teamsMessage,
} from "../forms/ListParts";
import { ModeTabs } from "../forms/ModeTabs";
import { useOutbox } from "../outbox/useOutbox";
import { PhotoSaveNote, PhotoStrip } from "../photos/PhotoStrip";
import { useEntryPhotos } from "../photos/useEntryPhotos";
import type { ScoutConfig, Values } from "../scout/config";
import { useTrainingSession } from "../training/session";
import { DeleteButton } from "../ui/DeleteButton";
import { TeamLink } from "../ui/TeamLink";
import { useOnline } from "../ui/useOnline";

type Filter = "todo" | "done" | "all";

const noKeys: string[] = [];

export function PitListRoute() {
  const auth = useAuth();
  const { eventKey, teams, status } = useTbaEvent();
  const feed = usePitEntries();
  const settled = useSettled(feed);
  const outbox = useOutbox();
  const online = useOnline();
  const navigate = useNavigate();
  const [filter, setFilter] = useState<Filter>("todo");
  const rows = useMemo(
    () => pitRows(teams, feed.items, eventKey),
    [teams, feed.items, eventKey],
  );
  const done = rows.filter((r) => r.done).length;
  const shown = rows.filter((r) =>
    filter === "all" ? true : filter === "done" ? r.done : !r.done,
  );

  return (
    <div className="forms-page">
      <ModeTabs />
      <ListHead
        title="Pit scouting"
        eventKey={eventKey}
        online={online}
        unsent={unsentCount(outbox, "pit")}
      />
      {auth.status === "signed-out" && (
        <p className="notice-soft">Sign in to see which teams are done.</p>
      )}
      {feed.failed && (
        <p className="notice" role="alert">
          Could not read the pit entries. The list may be incomplete.
        </p>
      )}
      {rows.length === 0 ? (
        <p className="secondary">{teamsMessage(eventKey, status)}</p>
      ) : !settled ? (
        <p className="secondary">Loading the pit entries.</p>
      ) : (
        <>
          <p className="progress">
            {done} of {rows.length} done
          </p>
          <FilterChips<Filter>
            label="Show teams"
            value={filter}
            onPick={setFilter}
            options={[
              { key: "todo", text: `Not done (${rows.length - done})` },
              { key: "done", text: `Done (${done})` },
              { key: "all", text: `All (${rows.length})` },
            ]}
          />
          {shown.length === 0 ? (
            <p className="secondary">No teams in this list.</p>
          ) : (
            <ul className="todo">
              {shown.map((r) => (
                <li key={r.team} className="todo-row">
                  <span className="todo-team">
                    <TeamLink team={r.team} />
                  </span>
                  <Link className="todo-open" to={`/scout/pit/${r.team}`}>
                    <span className="todo-name">{r.name}</span>
                    <span className="todo-state" data-done={r.done}>
                      {r.state}
                    </span>
                    {r.scouts.length > 0 && (
                      <span className="todo-note secondary">
                        {r.scouts.join(", ")}
                      </span>
                    )}
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      <OpenTeam onOpen={(team) => navigate(`/scout/pit/${team}`)} />
    </div>
  );
}

export function PitFormRoute() {
  const params = useParams();
  const team = parseTeamParam(params.team);
  if (team === null) {
    return (
      <div className="forms-page">
        <p className="notice">That is not a team number.</p>
        <Link className="btn" to="/scout/pit">
          Pit list
        </Link>
      </div>
    );
  }
  return (
    <PitFormFor key={`${team}/${params.id ?? ""}`} team={team} id={params.id} />
  );
}

function PitFormFor({ team, id }: { team: number; id: string | undefined }) {
  const auth = useAuth();
  const lead = useIsLead();
  const { eventKey } = useTbaEvent();
  const config = useFormConfig("pit");
  const feed = usePitEntries();
  const settled = useSettled(feed);
  const [loaded, setLoaded] = useState<{
    uid: string | null;
    entry: PitEntry | null;
  } | null>(null);

  useEffect(() => {
    if (!settled || (loaded !== null && loaded.uid === auth.uid)) return;
    setLoaded({
      uid: auth.uid,
      entry:
        id === undefined
          ? ownPitEntry(feed.items, team, auth.uid, eventKey)
          : (feed.items.find((e) => e.id === id && e.teamNumber === team) ??
            null),
    });
  }, [settled, loaded, feed.items, team, id, auth.uid, eventKey]);

  const back = (
    <Link className="btn back" to="/scout/pit">
      Pit list
    </Link>
  );
  if (loaded === null) {
    return (
      <div className="forms-page">
        {back}
        <p className="secondary">Loading the saved answers.</p>
      </div>
    );
  }
  if (id !== undefined && loaded.entry === null) {
    return (
      <div className="forms-page">
        {back}
        <p className="notice">That entry was not found.</p>
      </div>
    );
  }
  if (loaded.entry && loaded.entry.authorUid !== auth.uid && !lead) {
    return (
      <div className="forms-page">
        {back}
        <p className="notice">
          Only {loaded.entry.scoutName || "its author"} or a lead can change
          this entry.
        </p>
      </div>
    );
  }
  const formKey = JSON.stringify(
    config.sections.map((s) => [s.name, s.fields.map((f) => f.code)]),
  );
  return (
    <PitFormBody
      key={formKey}
      team={team}
      config={config}
      existing={loaded.entry}
      entries={feed.items}
      lead={lead}
    />
  );
}

function PitFormBody(props: {
  team: number;
  config: ScoutConfig;
  existing: PitEntry | null;
  entries: PitEntry[];
  lead: boolean;
}) {
  const { team, config, existing, entries, lead } = props;
  const { eventKey, teams } = useTbaEvent();
  const auth = useAuth();
  const navigate = useNavigate();
  const canDelete = useCanDelete(existing?.authorUid);
  const outbox = useOutbox();
  const online = useOnline();
  const [newId] = useState(() => crypto.randomUUID());
  const created = useRef(false);
  const id = existing?.id ?? newId;
  const draftKey = `ss.form.draft.pit.${eventKey}.${team}${existing ? `.${existing.id}` : ""}`;
  const [start] = useState(() => {
    const draft = readCache<Values>(draftKey);
    return {
      initial: startValues(config, existing?.fieldValues ?? null, draft),
      restored: draft !== null,
    };
  });
  const signedIn = auth.status === "signed-in" && auth.uid !== null;
  const name = teams.find((t) => t.number === team)?.nickname;
  const editingOther = existing !== null && existing.authorUid !== auth.uid;
  const others = pitEntriesFor(entries, team, eventKey).filter(
    (e) => e.id !== id && e.authorUid !== auth.uid,
  );

  const training = useTrainingSession() !== null;
  const photoEntry = pitEntriesFor(entries, team, eventKey)[0] ?? null;
  const photos = useEntryPhotos(
    { entryId: photoEntry?.id ?? null, team, eventKey },
    photoEntry?.photoKeys ?? noKeys,
  );

  async function save(values: Values) {
    const stored = entries.find((e) => e.id === id);
    const label = `Pit, team ${team}`;
    if (existing || stored || created.current) {
      await persistMerge(
        "pit",
        id,
        pitAnswersMerge(
          config,
          values,
          (stored ?? existing)?.stampMs,
          new Date(),
        ),
        label,
      );
      return;
    }
    const uid = auth.uid;
    if (!uid) throw new Error("Not signed in");
    await persistForm(
      "pit",
      formEntryDocument({
        kind: "pit",
        id,
        team,
        eventKey,
        config,
        values,
        authorUid: uid,
        authorDisplayName: auth.displayName || "",
        now: new Date(),
        photoKeys: [],
      }),
      label,
    );
    created.current = true;
  }

  return (
    <EntryForm
      config={config}
      initial={start.initial}
      restored={start.restored}
      draftKey={draftKey}
      entryId={id}
      title={`Team ${team}`}
      {...(name ? { subtitle: name } : {})}
      back={{ to: "/scout/pit", label: "Pit list" }}
      status={[
        eventKey || "No event",
        editingOther
          ? `Editing ${existing.scoutName || "another scout"}'s entry`
          : existing
            ? "Editing your saved entry"
            : "New entry",
      ]}
      signedIn={signedIn}
      online={online}
      unsent={unsentCount(outbox, "pit")}
      deliveryOf={(entry) => deliveryAt(outbox, "pit", entry)}
      save={save}
      savedTitle={`Team ${team} saved`}
      notice={
        others.length > 0 &&
        (lead ? (
          <div className="other-entries">
            <p className="notice-soft">
              Other scouts' entries for this team. A lead can correct them.
            </p>
            {others.map((e) => (
              <Link
                key={e.id}
                className="btn"
                to={`/scout/pit/${team}/${e.id}`}
              >
                Edit {e.scoutName || "another scout"}'s entry
              </Link>
            ))}
          </div>
        ) : (
          <p className="notice-soft">
            Also scouted by{" "}
            {others.map((e) => e.scoutName || "another scout").join(", ")}.
            Saving adds your own entry.
          </p>
        ))
      }
      savedNote={<PhotoSaveNote photos={photos} />}
      after={
        <>
          <PhotoStrip
            photos={photos}
            {...(training
              ? { blocked: "Training mode does not take photos." }
              : {})}
          />
          {existing && canDelete && (
            <DeleteButton
              what={`pit entry for team ${team}`}
              prompt={`Delete the pit entry for team ${team}? Its photos are deleted too.`}
              onConfirm={async () => {
                await deleteFormEntry(
                  "pit",
                  existing.id,
                  `Pit deleted, team ${team}`,
                  existing.photoKeys,
                );
                navigate("/scout/pit");
              }}
            />
          )}
        </>
      }
    />
  );
}
