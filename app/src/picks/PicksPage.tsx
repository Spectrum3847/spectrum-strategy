import { useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { Bracket } from "../bracket/Bracket";
import { robotsFor } from "../bracket/data";
import { Simulations } from "../bracket/Simulations";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { useFormConfig, usePitEntries } from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { useEpa } from "../match/useOutside";
import { useMyTeam } from "../now/myTeam";
import type { OutboxItem } from "../outbox/outbox";
import { dismissItem, enqueueDelete } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { useScoutData } from "../scout/ScoutData";
import { DeliveryLine } from "../scout/ScoutForm";
import { DeleteButton } from "../ui/DeleteButton";
import { useOnline } from "../ui/useOnline";
import { DraftView } from "./DraftView";
import { replayDraft, roundsForEventType, seeding, takenLabels } from "./draft";
import { setTaken, useDraftState } from "./draftStore";
import { useEventKind } from "./eventType";
import { buildFacts } from "./facts";
import { PickListView } from "./PickListView";
import { InlineForm } from "./parts";
import {
  applyLayout,
  applyName,
  type Layout,
  layoutOf,
  maxName,
  newList,
  type PickList,
  refusalNote,
} from "./pickList";
import { ReadOnlyList } from "./ReadOnlyList";
import { sentMs } from "./sentStamp";
import {
  lastWrittenMs,
  pickListPath,
  savePickList,
  usePickLists,
} from "./usePickLists";
import "./picks.css";

type View = "list" | "draft";

const clock = (ms: number) =>
  new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

function useRemoteChange(list: PickList | null) {
  const [seen] = useState(() => new Map<string, number>());
  const [note, setNote] = useState<string | null>(null);
  useEffect(() => {
    if (!list) return;
    const before = seen.get(list.id);
    seen.set(list.id, list.updatedMs);
    if (
      before !== undefined &&
      list.updatedMs > before &&
      list.updatedMs > lastWrittenMs(list.id)
    ) {
      setNote(
        `Another lead or device saved a newer version at ${clock(list.updatedMs)}. This list now shows it.`,
      );
    }
  }, [list, seen]);
  return [note, () => setNote(null)] as const;
}

function ListStatus({
  list,
  item,
  signedIn,
}: {
  list: PickList;
  item: OutboxItem | undefined;
  signedIn: boolean;
}) {
  const [note, dismissNote] = useRemoteChange(list);
  return (
    <div className="pick-status">
      {note && (
        <p className="notice-soft" role="status">
          {note}{" "}
          <button type="button" className="btn" onClick={dismissNote}>
            Dismiss
          </button>
        </p>
      )}
      {item?.status === "refused" && (
        <p className="notice" role="alert">
          {refusalNote(sentMs(item), list.updatedMs)}{" "}
          <button
            type="button"
            className="btn"
            onClick={() => dismissItem(item.id)}
          >
            Discard my change
          </button>
        </p>
      )}
      <p className="secondary" role="status">
        {item && item.status !== "refused" ? (
          <DeliveryLine
            delivery={{ status: item.status }}
            signedIn={signedIn}
          />
        ) : (
          `Last changed at ${clock(list.updatedMs)}`
        )}
      </p>
    </div>
  );
}

export function Picks() {
  const [search] = useSearchParams();
  const view: View = search.get("view") === "draft" ? "draft" : "list";
  const auth = useAuth();
  const roles = useRoles();
  const online = useOnline();
  const us = useMyTeam();
  const { config, eventKey, eventReady } = useScoutData();
  const tba = useTbaEvent();
  const entries = useCorrectedEntries(eventKey);
  const pit = usePitEntries();
  const pitConfig = useFormConfig("pit");
  const epa = useEpa(eventKey);
  const lists = usePickLists();
  const outbox = useOutbox();
  const kind = useEventKind(eventKey);
  const draft = useDraftState(eventKey);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  const signedIn = auth.status === "signed-in" && auth.uid !== null;
  const canEdit = roles.status === "ready" && isLead(roles.roles);
  const author = {
    uid: auth.uid ?? "",
    displayName:
      (roles.status === "ready" ? roles.displayName : "") ||
      auth.displayName ||
      "",
  };

  const facts = useMemo(
    () =>
      buildFacts({
        config,
        pitConfig,
        entries: entries.items,
        pit: pit.items,
        rankings: tba.rankings,
        epa: epa.data,
      }),
    [config, pitConfig, entries.items, pit.items, tba.rankings, epa.data],
  );
  const robots = useMemo(
    () => robotsFor(config, entries.items),
    [config, entries.items],
  );
  const [draftPart, setDraftPart] = useState<
    "draft" | "bracket" | "simulations"
  >("draft");
  const nicknames = useMemo(
    () => new Map(tba.teams.map((t) => [t.number, t.nickname])),
    [tba.teams],
  );
  const official = useMemo(
    () => tba.rankings.map((r) => r.team),
    [tba.rankings],
  );
  const ranking = useMemo(
    () =>
      seeding(
        official,
        epa.data,
        tba.teams.map((t) => t.number),
      ),
    [official, epa.data, tba.teams],
  );

  const rounds = draft.rounds ?? roundsForEventType(kind.type);
  const board = useMemo(
    () => replayDraft(draft.actions, ranking, rounds),
    [draft.actions, ranking, rounds],
  );
  const labels = useMemo(() => takenLabels(board), [board]);
  const takenJson = JSON.stringify(
    draft.actions.length > 0 ? [...labels.entries()] : [],
  );
  // biome-ignore lint/correctness/useExhaustiveDependencies: takenJson stands for labels.
  useEffect(() => {
    setTaken(
      eventKey,
      draft.actions.length > 0 ? Object.fromEntries(labels) : {},
    );
  }, [eventKey, takenJson]);

  const sorted = useMemo(
    () => [...lists.items].sort((a, b) => b.updatedMs - a.updatedMs),
    [lists.items],
  );
  const selected = sorted.find((l) => l.id === selectedId) ?? sorted[0] ?? null;
  const item = selected
    ? outbox.find((i) => i.path === pickListPath(selected.id))
    : undefined;

  const save = async (next: PickList, label: string) => {
    setSaveError(null);
    try {
      await savePickList(next, label);
    } catch (error) {
      console.error("Pick list save failed", error);
      setSaveError("Could not save this change on this device. Try again.");
    }
  };
  const onLayout = (layout: Layout) =>
    selected &&
    save(
      applyLayout(selected, layout, Date.now()),
      `Pick list ${selected.name}`,
    );
  const onRename = (name: string) =>
    selected &&
    save(applyName(selected, name, Date.now()), `Pick list ${selected.name}`);
  const create = async (name: string) => {
    const made = newList(name, author, Date.now());
    await save(made, `Pick list ${made.name}`);
    setSelectedId(made.id);
    setCreating(false);
  };

  const tabTo = (v: View) => ({ search: v === "draft" ? "?view=draft" : "" });
  const empty = lists.ready && sorted.length === 0;
  const eventLoading =
    (eventKey === "" && eventReady === false) ||
    (eventKey !== "" &&
      ranking.length === 0 &&
      (tba.status === "none" || tba.status === "loading")) ||
    (signedIn && eventKey !== "" && (!entries.ready || !pit.ready));

  return (
    <div className="picks">
      <h1>Picks</h1>
      <nav className="pick-tabs" aria-label="Picks sections">
        <Link
          className="btn"
          to={tabTo("list")}
          replace
          aria-current={view === "list" ? "page" : undefined}
        >
          Pick list
        </Link>
        <Link
          className="btn"
          to={tabTo("draft")}
          replace
          aria-current={view === "draft" ? "page" : undefined}
        >
          Draft board
        </Link>
        <Link className="btn" to="/picks/playoffs">
          Playoffs
        </Link>
      </nav>

      {!signedIn && (
        <p className="notice" role="status">
          Sign in to load pick lists.
        </p>
      )}
      {signedIn && !online && (
        <p className="notice-soft" role="status">
          Offline. This shows what this device last saved. Changes send when
          this device is back online.
        </p>
      )}
      {lists.failed && (
        <p className="notice" role="status">
          Could not read the latest pick lists. This may be incomplete.
        </p>
      )}
      {!canEdit && roles.status === "ready" && (
        <p className="secondary">
          You can read the pick lists but not change them.
        </p>
      )}
      {saveError && (
        <p className="notice" role="alert">
          {saveError}
        </p>
      )}
      {eventLoading && (
        <p className="secondary" role="status">
          Loading event and scouting data.
        </p>
      )}
      {eventKey === "" && eventReady !== false && (
        <p className="secondary">
          No event is set, so there are no event teams. Pick one in Settings.
        </p>
      )}
      {tba.status === "failed" && tba.fetchedAt === null && eventKey !== "" && (
        <p className="secondary" role="status">
          Team names and ranks need a connection the first time.
        </p>
      )}

      {eventLoading ? null : view === "draft" ? (
        <>
          <fieldset className="chips" aria-label="Draft board sections">
            {(["draft", "bracket", "simulations"] as const).map((part) => (
              <button
                type="button"
                className="chip"
                key={part}
                aria-pressed={draftPart === part}
                onClick={() => setDraftPart(part)}
              >
                {part === "draft"
                  ? "Selection"
                  : part === "bracket"
                    ? "Bracket"
                    : "Simulations"}
              </button>
            ))}
          </fieldset>
          {draftPart === "bracket" ? (
            <Bracket
              alliances={board.alliances.map((a) => a.teams)}
              robots={robots}
            />
          ) : draftPart === "simulations" && !canEdit ? (
            <p>Simulations are available to strategy leads.</p>
          ) : draftPart === "simulations" ? (
            <Simulations
              key={eventKey}
              eventKey={eventKey}
              ranking={ranking}
              official={official}
              rounds={rounds}
              us={us}
              layout={selected ? layoutOf(selected) : null}
              robots={robots}
            />
          ) : (
            <DraftView
              eventKey={eventKey}
              canEdit={canEdit}
              board={board}
              actions={draft.actions}
              rounds={rounds}
              roundsFrom={draft.rounds === null ? kind.name : ""}
              facts={facts}
              layout={selected ? layoutOf(selected) : null}
              ranking={ranking}
              official={official}
              us={us}
            />
          )}
        </>
      ) : (
        <>
          <div className="pick-lists">
            {sorted.length > 0 && (
              <fieldset className="chips" aria-label="Pick lists">
                {sorted.map((l) => (
                  <button
                    key={l.id}
                    type="button"
                    className="chip"
                    aria-pressed={selected?.id === l.id}
                    onClick={() => setSelectedId(l.id)}
                  >
                    {l.name}
                  </button>
                ))}
              </fieldset>
            )}
            {canEdit && (
              <button
                type="button"
                className="btn"
                aria-expanded={creating}
                disabled={!signedIn}
                onClick={() => setCreating(!creating)}
              >
                New list
              </button>
            )}
          </div>
          {creating && canEdit && (
            <InlineForm
              fields={[
                { label: "List name", initial: "Pick list", max: maxName },
              ]}
              submit="Create list"
              validate={([name]) =>
                name === "" ? "Give the list a name." : null
              }
              onSubmit={([name]) => void create(name ?? "")}
            />
          )}
          {!lists.ready && (
            <p className="secondary" role="status">
              {online
                ? "Loading pick lists."
                : "Pick lists load from this device. If none appear, connect once to load them."}
            </p>
          )}
          {empty && !creating && (
            <p className="secondary">
              {canEdit
                ? "No pick lists yet. Create one to rank teams for alliance selection."
                : "No pick lists yet."}
            </p>
          )}
          {selected && (
            <>
              <ListStatus list={selected} item={item} signedIn={signedIn} />
              {canEdit ? (
                <PickListView
                  key={selected.id}
                  list={selected}
                  facts={facts}
                  nicknames={nicknames}
                  eventTeams={ranking}
                  taken={labels}
                  us={us}
                  onLayout={(layout) => void onLayout(layout)}
                  onRename={(name) => void onRename(name)}
                />
              ) : (
                <ReadOnlyList list={selected} facts={facts} taken={labels} />
              )}
              {canEdit && (
                <div className="actions">
                  <DeleteButton
                    what={`pick list ${selected.name}`}
                    prompt={`Delete "${selected.name}"? Everyone on the team loses this list.`}
                    onConfirm={async () => {
                      await enqueueDelete(
                        pickListPath(selected.id),
                        `Pick list ${selected.name} deleted`,
                      );
                      setSelectedId(null);
                    }}
                  />
                </div>
              )}
            </>
          )}
        </>
      )}
    </div>
  );
}
