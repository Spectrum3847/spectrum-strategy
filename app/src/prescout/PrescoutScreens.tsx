import { useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { readCache } from "../data/cache";
import type { PrescoutEntry } from "../data/parse";
import { useFormConfig, usePrescoutEntries } from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { startValues } from "../forms/config";
import { deleteFormEntry, useCanDelete } from "../forms/deleteEntry";
import { deliveryAt, persistForm, unsentCount } from "../forms/delivery";
import { formEntryDocument } from "../forms/document";
import { EntryForm } from "../forms/EntryForm";
import {
  entryMatchLabel,
  isDuplicateRecord,
  prescoutMatchLabel,
  prescoutPerTeam,
  prescoutRecords,
  prescoutRows,
  splitLegacyLabel,
  watchedMatchId,
} from "../forms/entries";
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
import type { ScoutConfig, Values } from "../scout/config";
import { DeliveryLine } from "../scout/ScoutForm";
import { DeleteButton } from "../ui/DeleteButton";
import { TeamLink } from "../ui/TeamLink";
import { useOnline } from "../ui/useOnline";
import { FilmPane } from "./FilmPane";
import { MatchPicker } from "./MatchPicker";
import { RecordView } from "./RecordView";
import { usePrescoutPlan } from "./usePrescoutPlan";

type Filter = "open" | "done" | "all";

export function PrescoutListRoute() {
  const auth = useAuth();
  const { eventKey, teams, status } = useTbaEvent();
  const feed = usePrescoutEntries();
  const settled = useSettled(feed);
  const outbox = useOutbox();
  const online = useOnline();
  const navigate = useNavigate();
  const [filter, setFilter] = useState<Filter>("open");
  const rows = useMemo(
    () => prescoutRows(teams, feed.items, eventKey),
    [teams, feed.items, eventKey],
  );
  const complete = rows.filter((r) => r.complete).length;
  const shown = rows.filter((r) =>
    filter === "all" ? true : filter === "done" ? r.complete : !r.complete,
  );

  return (
    <div className="forms-page">
      <ModeTabs />
      <ListHead
        title="Prescout"
        eventKey={eventKey}
        online={online}
        unsent={unsentCount(outbox, "prescout")}
      />
      {auth.status === "signed-out" && (
        <p className="notice-soft">Sign in to see the records saved so far.</p>
      )}
      {feed.failed && (
        <p className="notice" role="alert">
          Could not read the prescout records. The list may be incomplete.
        </p>
      )}
      {rows.length === 0 ? (
        <p className="secondary">{teamsMessage(eventKey, status)}</p>
      ) : !settled ? (
        <p className="secondary">Loading the prescout records.</p>
      ) : (
        <>
          <p className="progress">
            {complete} of {rows.length} teams done
          </p>
          <FilterChips<Filter>
            label="Show teams"
            value={filter}
            onPick={setFilter}
            options={[
              { key: "open", text: `Not done (${rows.length - complete})` },
              { key: "done", text: `Done (${complete})` },
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
                  <Link className="todo-open" to={`/scout/prescout/${r.team}`}>
                    <span className="todo-name">{r.name}</span>
                    <span className="todo-state" data-done={r.complete}>
                      {r.count} of {prescoutPerTeam}
                    </span>
                    {r.starter && (
                      <span className="todo-note secondary">
                        Started by {r.starter}
                      </span>
                    )}
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </>
      )}
      <OpenTeam onOpen={(team) => navigate(`/scout/prescout/${team}`)} />
    </div>
  );
}

function BadTeam() {
  return (
    <div className="forms-page">
      <p className="notice">That is not a team number.</p>
      <Link className="btn" to="/scout/prescout">
        Prescout list
      </Link>
    </div>
  );
}

export function PrescoutTeamRoute() {
  const team = parseTeamParam(useParams().team);
  return team === null ? <BadTeam /> : <PrescoutTeam team={team} />;
}

function PrescoutTeam({ team }: { team: number }) {
  const auth = useAuth();
  const lead = useIsLead();
  const { eventKey, teams } = useTbaEvent();
  const feed = usePrescoutEntries();
  const settled = useSettled(feed);
  const outbox = useOutbox();
  const records = prescoutRecords(feed.items, team, eventKey);
  const name = teams.find((t) => t.number === team)?.nickname;
  const addable = eventKey !== "" && records.length < prescoutPerTeam;

  return (
    <div className="forms-page">
      <Link className="btn back" to="/scout/prescout">
        Prescout list
      </Link>
      <header className="forms-head">
        <h1>Team {team}</h1>
        <p className="status-line secondary">
          {name && <span>{name}</span>}
          <span>{eventKey || "No event"}</span>
          <span>
            {records.length} of {prescoutPerTeam} records
          </span>
        </p>
      </header>
      {!settled ? (
        <p className="secondary">Loading the records.</p>
      ) : (
        <>
          {records.length === 0 ? (
            <p className="secondary">No records for this team yet.</p>
          ) : (
            <ul className="outbox records">
              {records.map((e) => {
                const own = e.authorUid === auth.uid;
                const delivery = deliveryAt(outbox, "prescout", e.id);
                return (
                  <li key={e.id}>
                    <div className="saved-info">
                      <span className="record-label">
                        {entryMatchLabel(e) || "No match named"}
                      </span>
                      <span className="secondary">
                        {String(e.fieldValues.watchedEvent ?? "") || "No event"}
                        {" - "}
                        {own ? "You" : e.scoutName || "Another scout"}
                      </span>
                      {delivery && (
                        <DeliveryLine
                          delivery={delivery}
                          signedIn={auth.status === "signed-in"}
                        />
                      )}
                    </div>
                    <Link
                      className="btn"
                      to={`/scout/prescout/${team}/${e.id}`}
                    >
                      {own || lead ? "Edit" : "View"}
                    </Link>
                  </li>
                );
              })}
            </ul>
          )}
          {addable ? (
            <Link
              className="btn primary big"
              to={`/scout/prescout/${team}/new`}
            >
              Add record
            </Link>
          ) : (
            <p className="secondary">
              {eventKey === ""
                ? "No event is set. Set one in Settings before adding records."
                : `Team ${team} has all ${prescoutPerTeam} records.`}
            </p>
          )}
        </>
      )}
    </div>
  );
}

export function PrescoutFormRoute() {
  const params = useParams();
  const team = parseTeamParam(params.team);
  const id = params.id ?? "new";
  return team === null ? (
    <BadTeam />
  ) : (
    <PrescoutFormFor key={`${team}/${id}`} team={team} id={id} />
  );
}

interface Loaded {
  uid: string | null;
  existing: PrescoutEntry | null;
  full: boolean;
}

function PrescoutFormFor({ team, id }: { team: number; id: string }) {
  const auth = useAuth();
  const lead = useIsLead();
  const { eventKey } = useTbaEvent();
  const config = useFormConfig("prescout");
  const feed = usePrescoutEntries();
  const settled = useSettled(feed);
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const back = `/scout/prescout/${team}`;

  useEffect(() => {
    if (!settled || (loaded !== null && loaded.uid === auth.uid)) return;
    setLoaded({
      uid: auth.uid,
      existing:
        id === "new"
          ? null
          : (feed.items.find((e) => e.id === id && e.teamNumber === team) ??
            null),
      full:
        prescoutRecords(feed.items, team, eventKey).length >= prescoutPerTeam,
    });
  }, [settled, loaded, feed.items, team, id, auth.uid, eventKey]);

  const backLink = (
    <Link className="btn back" to={back}>
      Team {team}
    </Link>
  );
  if (loaded === null) {
    return (
      <div className="forms-page">
        {backLink}
        <p className="secondary">Loading the record.</p>
      </div>
    );
  }
  if (id !== "new" && loaded.existing === null) {
    return (
      <div className="forms-page">
        {backLink}
        <p className="notice">That record was not found.</p>
      </div>
    );
  }
  if (loaded.existing && loaded.existing.authorUid !== auth.uid && !lead) {
    return <RecordView config={config} entry={loaded.existing} back={back} />;
  }
  if (id === "new" && eventKey === "") {
    return (
      <div className="forms-page">
        {backLink}
        <p className="notice">
          No event is set. Set one in Settings before adding records.
        </p>
      </div>
    );
  }
  if (id === "new" && loaded.full) {
    return (
      <div className="forms-page">
        {backLink}
        <p className="notice">
          Team {team} already has all {prescoutPerTeam} records.
        </p>
      </div>
    );
  }
  const formKey = JSON.stringify(
    config.sections.map((s) => [s.name, s.fields.map((f) => f.code)]),
  );
  return (
    <PrescoutFormBody
      key={formKey}
      team={team}
      id={id}
      config={config}
      existing={loaded.existing}
      entries={feed.items}
    />
  );
}

function PrescoutFormBody(props: {
  team: number;
  id: string;
  config: ScoutConfig;
  existing: PrescoutEntry | null;
  entries: PrescoutEntry[];
}) {
  const { team, config, existing, entries } = props;
  const event = useTbaEvent();
  const auth = useAuth();
  const navigate = useNavigate();
  const canDelete = useCanDelete(existing?.authorUid);
  const outbox = useOutbox();
  const online = useOnline();
  const [newId] = useState(() => crypto.randomUUID());
  const entryId = existing?.id ?? newId;
  const eventKey = existing ? existing.eventKey : event.eventKey;
  const draftKey = `ss.form.draft.prescout.${eventKey}.${team}.${props.id}`;
  const [start] = useState(() => {
    const draft = readCache<Values>(draftKey);
    return {
      initial: startValues(
        config,
        existing ? splitLegacyLabel(existing.fieldValues) : null,
        draft,
      ),
      restored: draft !== null,
    };
  });
  const signedIn = auth.status === "signed-in" && auth.uid !== null;
  const name = event.teams.find((t) => t.number === team)?.nickname;
  const editingOther = existing !== null && existing.authorUid !== auth.uid;
  const taken = prescoutRecords(entries, team, eventKey).length;
  const plan = usePrescoutPlan(team, eventKey);
  const recorded = useMemo(
    () =>
      new Set(
        prescoutRecords(entries, team, eventKey)
          .filter((e) => e.id !== entryId)
          .map((e) =>
            watchedMatchId(e.fieldValues.watchedEvent, entryMatchLabel(e)),
          ),
      ),
    [entries, team, eventKey, entryId],
  );

  function check(values: Values): string | null {
    if (!isDuplicateRecord(entries, team, eventKey, values, entryId)) {
      return null;
    }
    const label = prescoutMatchLabel(values.matchType, values.matchNumber);
    const watched = String(values.watchedEvent ?? "").trim();
    return `Team ${team} already has a record for ${label}${watched ? ` at ${watched}` : ""}.`;
  }

  async function save(values: Values) {
    const uid = existing?.authorUid || auth.uid;
    if (!uid) throw new Error("Not signed in");
    const doc = formEntryDocument({
      kind: "prescout",
      id: entryId,
      team,
      eventKey,
      config,
      values,
      authorUid: uid,
      authorDisplayName: existing?.scoutName || auth.displayName || "",
      now: new Date(),
    });
    const label = prescoutMatchLabel(values.matchType, values.matchNumber);
    await persistForm(
      "prescout",
      doc,
      `Prescout, team ${team}${label ? ` ${label}` : ""}`,
    );
  }

  return (
    <EntryForm
      config={config}
      initial={start.initial}
      restored={start.restored}
      draftKey={draftKey}
      entryId={entryId}
      title={`Team ${team}`}
      {...(name ? { subtitle: name } : {})}
      back={{ to: `/scout/prescout/${team}`, label: `Team ${team}` }}
      status={[
        eventKey || "No event",
        editingOther
          ? `Editing ${existing.scoutName || "another scout"}'s record`
          : existing
            ? "Editing your record"
            : `Record ${Math.min(taken + 1, prescoutPerTeam)} of ${prescoutPerTeam}`,
      ]}
      signedIn={signedIn}
      online={online}
      unsent={unsentCount(outbox, "prescout")}
      deliveryOf={(entry) => deliveryAt(outbox, "prescout", entry)}
      save={save}
      check={check}
      above={({ values, patch }) => (
        <MatchPicker
          state={plan}
          values={values}
          recorded={recorded}
          autopick={existing === null}
          onPick={patch}
        />
      )}
      beside={(values) => {
        const url = String(values.videoUrl ?? "").trim();
        return url === "" ? null : <FilmPane url={url} />;
      }}
      savedTitle={`Team ${team} record saved`}
      after={
        existing &&
        canDelete && (
          <DeleteButton
            what={`prescout record for team ${team}`}
            prompt={`Delete this prescout record for team ${team}?`}
            onConfirm={async () => {
              await deleteFormEntry(
                "prescout",
                existing.id,
                `Prescout deleted, team ${team}`,
              );
              navigate(`/scout/prescout/${team}`);
            }}
          />
        )
      }
    />
  );
}
