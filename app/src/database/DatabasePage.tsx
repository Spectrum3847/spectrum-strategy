import { useLayoutEffect, useMemo, useRef, useState } from "react";
import { Link } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { applyCorrections } from "../corrections/apply";
import { correctableFields } from "../corrections/fields";
import { HistoryDialog } from "../corrections/HistoryDialog";
import { historyList } from "../corrections/history";
import { entryLabel } from "../corrections/rows";
import { CorrectionDelivery, useCorrector } from "../corrections/useCorrect";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import type { FormEntry, PitEntry } from "../data/parse";
import type { Feed } from "../data/store";
import {
  useFormConfig,
  usePitEntries,
  usePrescoutEntries,
} from "../data/useCollections";
import { useCorrections } from "../data/useCorrections";
import { deleteFormEntry, useDeleteGate } from "../forms/deleteEntry";
import { enqueueDelete } from "../outbox/outbox";
import { useScoutData } from "../scout/ScoutData";
import { useOnline } from "../ui/useOnline";
import { Browse } from "./Browse";
import { CorrectEntry } from "./CorrectEntry";
import type { Remover } from "./DbTable";
import { detectFlags } from "./flags";
import { refreshFromServer } from "./refresh";
import { type Kind, matchRows, recordFields, recordRows } from "./rows";
import { seasonOf, useAllEntries } from "./useAllEntries";
import { useCellEditor } from "./useCellEditor";
import "./database.css";

const kinds: { kind: Kind; label: string }[] = [
  { kind: "match", label: "Match entries" },
  { kind: "pit", label: "Pit" },
  { kind: "prescout", label: "Prescout" },
];

function MatchView({ allEvents }: { allEvents: boolean }) {
  const { config, eventKey, schedule } = useScoutData();
  const eventFeed = useCorrectedEntries(eventKey);
  const season = seasonOf(eventKey);
  const everything = useAllEntries(allEvents, season);
  const corrections = useCorrections(eventKey);
  const everyItem = useMemo(
    () => applyCorrections(everything.items, corrections.items),
    [everything.items, corrections.items],
  );
  const feed = allEvents
    ? {
        ...eventFeed,
        items: everyItem,
        ready: everything.ready,
        failed: everything.failed,
      }
    : eventFeed;
  const corrector = useCorrector(eventKey);
  const canCorrect = corrector.canCorrect && !allEvents;
  const flags = useMemo(
    () =>
      detectFlags(
        eventFeed.items,
        schedule.filter((m) => m.compLevel === "qm").map((m) => m.matchNumber),
      ),
    [eventFeed.items, schedule],
  );
  const rows = useMemo(() => matchRows(feed.items, flags), [feed.items, flags]);
  const fields = useMemo(() => correctableFields(config), [config]);
  const [editing, setEditing] = useState<string | null>(null);
  const [history, setHistory] = useState<string | null>(null);
  const cells = useCellEditor(eventKey, fields, (id) =>
    feed.items.find((e) => e.id === id),
  );
  const scrollY = useRef(0);
  const gate = useDeleteGate();
  const remover: Remover = {
    can: (row) => gate(row.authorUid),
    run: (row) =>
      enqueueDelete(
        `scoutEntries/${row.id}`,
        `Team ${row.team}, ${row.label} deleted`,
      ).then(() => undefined),
  };
  const entry =
    editing === null ? null : feed.items.find((e) => e.id === editing);
  const past =
    history === null ? null : feed.items.find((e) => e.id === history);

  useLayoutEffect(() => {
    window.scrollTo(0, editing === null ? scrollY.current : 0);
  }, [editing]);

  const open = (id: string) => {
    scrollY.current = window.scrollY;
    setEditing(id);
  };

  return (
    <>
      {entry && (
        <CorrectEntry
          entry={entry}
          eventKey={eventKey}
          config={config}
          onBack={() => setEditing(null)}
        />
      )}
      <div hidden={!!entry} className="db-body">
        {eventKey === "" ? (
          <p className="secondary" role="status">
            Set an event in Settings to see its entries.
          </p>
        ) : (
          <>
            {feed.failed && (
              <p className="notice" role="alert">
                Entries could not be fully loaded, so this list may be
                incomplete.
              </p>
            )}
            {feed.correctionsFailed && (
              <p className="notice" role="alert">
                Corrections could not be loaded, so some values may show as the
                scout entered them.
              </p>
            )}
            {rows.length === 0 && (
              <p className="secondary" role="status">
                {feed.ready
                  ? allEvents
                    ? `No scout entries for ${season} yet.`
                    : `No scout entries for ${eventKey} yet.`
                  : "Loading entries."}
              </p>
            )}
            {allEvents && (
              <p className="secondary" role="status">
                Every {season} event's entries. Switch to This event to correct
                entries.
              </p>
            )}
            <Browse
              kind="match"
              rows={rows}
              fields={fields}
              onCorrect={canCorrect ? open : undefined}
              onHistory={setHistory}
              editor={canCorrect ? cells.editor : undefined}
              remover={remover}
            />
            <div className="db-editstatus" role="status">
              {cells.message !== "" && (
                <p className="notice">{cells.message}</p>
              )}
              {cells.last && (
                <p className="secondary">
                  {`${cells.last.what}. `}
                  <CorrectionDelivery entryId={cells.last.entryId} />
                </p>
              )}
            </div>
            {past && (
              <HistoryDialog
                title={`History for team ${past.teamNumber}, ${entryLabel(past)}`}
                changes={historyList(
                  past.correction,
                  past.corrected,
                  past.rawValues,
                  past.fieldValues,
                )}
                fields={fields}
                onClose={() => setHistory(null)}
              />
            )}
          </>
        )}
      </div>
    </>
  );
}

function RecordView({
  kind,
  feed,
}: {
  kind: "pit" | "prescout";
  feed: Feed<FormEntry>;
}) {
  const config = useFormConfig(kind);
  const rows = useMemo(() => recordRows(feed.items), [feed.items]);
  const fields = useMemo(() => recordFields(config), [config]);
  const gate = useDeleteGate();
  const remover: Remover = {
    can: (row) => gate(row.authorUid),
    run: (row) => {
      const photoKeys =
        kind === "pit"
          ? ((feed.items.find((e) => e.id === row.id) as PitEntry | undefined)
              ?.photoKeys ?? [])
          : [];
      return deleteFormEntry(
        kind,
        row.id,
        `${kind === "pit" ? "Pit" : "Prescout"} deleted, team ${row.team}`,
        photoKeys,
      );
    },
  };
  return (
    <div className="db-body">
      {feed.failed && (
        <p className="notice" role="alert">
          Entries could not be fully loaded, so this list may be incomplete.
        </p>
      )}
      {rows.length === 0 && (
        <p className="secondary" role="status">
          {feed.ready ? "No entries yet." : "Loading entries."}
        </p>
      )}
      <Browse kind={kind} rows={rows} fields={fields} remover={remover} />
    </div>
  );
}

const PitView = () => <RecordView kind="pit" feed={usePitEntries()} />;
const PrescoutView = () => (
  <RecordView kind="prescout" feed={usePrescoutEntries()} />
);

export function Database() {
  const { eventKey } = useScoutData();
  const roles = useRoles();
  const signedIn = useAuth().status === "signed-in";
  const online = useOnline();
  const [kind, setKind] = useState<Kind>("match");
  const [allEvents, setAllEvents] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [refreshNote, setRefreshNote] = useState("");
  const all = allEvents && kind === "match";
  const lead = roles.status === "ready" && isLead(roles.roles);

  async function refresh() {
    setRefreshing(true);
    setRefreshNote("");
    try {
      await refreshFromServer(kind, eventKey, all);
      setRefreshNote("Up to date with the database.");
    } catch {
      setRefreshNote(
        "Could not reach the database. Showing what this device has.",
      );
    } finally {
      setRefreshing(false);
    }
  }

  return (
    <div className="db">
      <header className="db-head">
        <h1>Database</h1>
        {eventKey !== "" && <p className="secondary">{eventKey}</p>}
      </header>
      {!online && (
        <p className="notice-soft" role="status">
          Offline. Showing the entries saved on this device.
        </p>
      )}
      <div className="actions db-actions">
        <button
          type="button"
          className="btn"
          disabled={refreshing || !signedIn || !online}
          onClick={() => void refresh()}
        >
          {refreshing ? "Refreshing" : "Refresh"}
        </button>
        {kind === "match" && eventKey !== "" && (
          <fieldset className="db-kinds">
            <legend className="sr-only">Events shown</legend>
            <button
              type="button"
              className="chip"
              aria-pressed={!allEvents}
              onClick={() => setAllEvents(false)}
            >
              This event
            </button>
            <button
              type="button"
              className="chip"
              aria-pressed={allEvents}
              onClick={() => setAllEvents(true)}
            >
              All {seasonOf(eventKey)} events
            </button>
          </fieldset>
        )}
        {lead && (
          <Link className="btn" to="/scout/accuracy">
            Scout accuracy
          </Link>
        )}
      </div>
      {refreshNote && (
        <p className="secondary" role="status">
          {refreshNote}
        </p>
      )}
      <fieldset className="db-kinds">
        <legend className="sr-only">Collection</legend>
        {kinds.map((k) => (
          <button
            key={k.kind}
            type="button"
            className="chip"
            aria-pressed={kind === k.kind}
            onClick={() => setKind(k.kind)}
          >
            {k.label}
          </button>
        ))}
      </fieldset>
      {kind === "match" ? (
        <MatchView allEvents={allEvents} />
      ) : kind === "pit" ? (
        <PitView />
      ) : (
        <PrescoutView />
      )}
    </div>
  );
}
