import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useSearchParams } from "react-router";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { useFormConfig, usePitEntries } from "../data/useCollections";
import { incidentsByTeam } from "../picks/incidents";
import { useScoutData } from "../scout/ScoutData";
import { DeliveryLine } from "../scout/ScoutForm";
import { useTeamData } from "../teams/useTeamData";
import { useOnline } from "../ui/useOnline";
import { AllianceGrid, type BoardEdit, MeetingBoard } from "./Boards";
import {
  type CellRef,
  clearCell,
  isCell,
  labelOf,
  move,
  nextUp,
  type PlayoffBoard,
  readingOrder,
  type Source,
  setCell,
  setLabel,
  setStyle,
  styleOf,
} from "./board";
import {
  cardColors,
  cardedTeams,
  panelFacts,
  rankedTeams,
  tankTeams,
} from "./derive";
import { useCellDrag } from "./drag";
import {
  NextUp,
  type Panel,
  RankedList,
  TeamNumbers,
  VideoList,
} from "./Lists";
import { useSharedBoard } from "./useSharedBoard";
import { useQualVideos } from "./videos";
import "../picks/picks.css";
import "./playoffs.css";

type Part = "meeting" | "alliances";

function Toolbar({
  board,
  active,
  moving,
  onStyle,
  onClear,
  onCancel,
}: {
  board: PlayoffBoard;
  active: CellRef | null;
  moving: Source | null;
  onStyle(key: "highlighted" | "italic"): void;
  onClear(): void;
  onCancel(): void;
}) {
  const style = active ? styleOf(board, active.row, active.column) : null;
  return (
    <div className="pl-toolbar">
      {moving ? (
        <p role="status" className="pl-moving">
          {moving.kind === "team"
            ? `Holding ${moving.team}. Tap a grip on the board to place it.`
            : "Holding a cell. Tap another grip to swap, or the same one to put it down."}{" "}
          <button type="button" className="btn" onClick={onCancel}>
            Cancel
          </button>
        </p>
      ) : (
        <>
          <p className="secondary" role="status">
            {active
              ? `Selected: ${labelOf(board, active.column)} row ${active.row + 1}`
              : "Select a cell to mark it."}
          </p>
          <div className="actions">
            <button
              type="button"
              className="btn"
              aria-pressed={style?.highlighted ?? false}
              disabled={active === null}
              onClick={() => onStyle("highlighted")}
            >
              Highlight
            </button>
            <button
              type="button"
              className="btn"
              aria-pressed={style?.italic ?? false}
              disabled={active === null}
              onClick={() => onStyle("italic")}
            >
              Italic
            </button>
            <button
              type="button"
              className="btn"
              disabled={active === null}
              onClick={onClear}
            >
              Clear cell
            </button>
          </div>
        </>
      )}
    </div>
  );
}

const when = (ms: number) => {
  const d = new Date(ms);
  const sameDay = d.toDateString() === new Date().toDateString();
  return d.toLocaleString([], {
    ...(sameDay ? {} : { weekday: "short" }),
    hour: "numeric",
    minute: "2-digit",
  });
};

function BoardStatus({
  shared,
  lead,
}: {
  shared: ReturnType<typeof useSharedBoard>;
  lead: boolean;
}) {
  return (
    <div className="pl-status" role="status">
      <p className="secondary">
        {lead
          ? "Every lead shares this board. The last change wins."
          : "Strategy leads keep this board. It updates as they change it."}{" "}
        {shared.ms > 0
          ? `Last changed by ${shared.by || "a lead"} at ${when(shared.ms)}.`
          : "Nobody has changed it yet."}
      </p>
      {lead && shared.item && (
        <DeliveryLine
          delivery={{
            status: shared.item.status,
            ...(shared.item.error ? { error: shared.item.error } : {}),
          }}
          signedIn={shared.signedIn}
        />
      )}
    </div>
  );
}

function Body({ eventKey, lead }: { eventKey: string; lead: boolean }) {
  const online = useOnline();
  const { config } = useScoutData();
  const { tba, entries, rows } = useTeamData();
  const pit = usePitEntries();
  const pitConfig = useFormConfig("pit");
  const videos = useQualVideos(eventKey, true);

  const [part, setPart] = useSearchParams();
  const view: Part = part.get("part") === "alliances" ? "alliances" : "meeting";

  const shared = useSharedBoard(eventKey, lead);
  const { board, change } = shared;
  const [moving, setMoving] = useState<Source | null>(null);
  const [active, setActive] = useState<CellRef | null>(null);

  const drop = useCallback(
    (from: Source, to: CellRef) => {
      change((b) => move(b, from, to));
      setMoving(null);
    },
    [change],
  );
  const drag = useCellDrag(drop);

  useEffect(() => {
    if (!moving) return;
    const onKey = (ev: KeyboardEvent) => {
      if (ev.key === "Escape") setMoving(null);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [moving]);

  const signedIn = shared.signedIn;
  const ranked = useMemo(() => rankedTeams(rows), [rows]);
  const incidents = useMemo(
    () => incidentsByTeam(entries.items),
    [entries.items],
  );
  const colors = useMemo(() => cardColors(incidents), [incidents]);
  const carded = useMemo(() => cardedTeams(colors), [colors]);
  const tank = useMemo(
    () => tankTeams(pit.items, pitConfig),
    [pit.items, pitConfig],
  );
  const upNext = useMemo(() => nextUp(board), [board]);
  const panels = useMemo<Panel[]>(
    () =>
      upNext.map((team) => {
        const row = rows.find((r) => r.team === team) ?? null;
        return {
          team,
          nickname:
            row?.nickname ??
            tba.teams.find((t) => t.number === team)?.nickname ??
            "",
          card: colors.get(team),
          facts: panelFacts(team, {
            config,
            pitConfig,
            entries: entries.items,
            pit: pit.items,
          }),
        };
      }),
    [
      upNext,
      rows,
      tba.teams,
      colors,
      config,
      pitConfig,
      entries.items,
      pit.items,
    ],
  );

  const edit: BoardEdit = {
    readOnly: !lead,
    board,
    drag,
    moving,
    cards: colors,
    onText: (ref, text) => change((b) => setCell(b, ref, text)),
    onLabel: (column, text) => change((b) => setLabel(b, column, text)),
    onFocus: setActive,
    onHandle: (ref) => {
      if (moving === null) {
        setMoving({ kind: "cell", ...ref });
        return;
      }
      if (
        moving.kind === "cell" &&
        moving.grid === ref.grid &&
        moving.row === ref.row &&
        moving.column === ref.column
      ) {
        setMoving(null);
        return;
      }
      drop(moving, ref);
    },
  };

  const pickTeam = (team: number) =>
    setMoving(
      moving?.kind === "team" && moving.team === team
        ? null
        : { kind: "team", team },
    );

  const toolbar = (
    <Toolbar
      board={board}
      active={active && isCell(active) ? active : null}
      moving={moving}
      onCancel={() => setMoving(null)}
      onStyle={(key) => {
        if (!active) return;
        change((b) => {
          const now = styleOf(b, active.row, active.column);
          return setStyle(b, active.row, active.column, {
            ...now,
            [key]: !now[key],
          });
        });
      }}
      onClear={() => {
        if (active) change((b) => clearCell(b, active));
      }}
    />
  );

  const lists = (
    <>
      <div className="pl-side">
        <TeamNumbers
          title="Tank drivetrain"
          teams={tank}
          empty="No tank drivetrain teams pit scouted."
        />
        <TeamNumbers
          title="Yellow or red card"
          teams={carded}
          empty="No cards recorded."
        />
        <VideoList matches={tba.matches} videos={videos} />
      </div>
    </>
  );

  return (
    <>
      {signedIn && !online && (
        <p className="notice-soft" role="status">
          Offline. Scouting numbers are what this device last loaded.
        </p>
      )}
      {signedIn && !entries.ready && (
        <p className="secondary" role="status">
          Loading scouting data.
        </p>
      )}
      {!shared.kept && lead && (
        <p className="notice" role="alert">
          This device would not keep a copy of the board. It still sends while
          this page stays open.
        </p>
      )}
      {shared.queueFailed && (
        <p className="notice" role="alert">
          The board could not be queued for sending. Make another change to try
          again.
        </p>
      )}
      {shared.failed && (
        <p className="notice-soft" role="status">
          Could not read the shared board. This is the copy on this device.
        </p>
      )}
      {shared.offer && (
        <section className="pl-offer" aria-labelledby="pl-offer-h">
          <h2 id="pl-offer-h">Board saved on this device</h2>
          <p>
            This device has a playoff board from before boards were shared.
            Upload it so every lead sees it. It replaces the shared board.
          </p>
          <div className="actions">
            <button
              type="button"
              className="btn primary"
              onClick={shared.upload}
            >
              Upload this board
            </button>
            <button type="button" className="btn" onClick={shared.discard}>
              Discard it
            </button>
          </div>
        </section>
      )}
      <BoardStatus shared={shared} lead={lead} />
      <fieldset className="chips" aria-label="Playoff section">
        {(["meeting", "alliances"] as const).map((p) => (
          <button
            key={p}
            type="button"
            className="chip"
            aria-pressed={view === p}
            onClick={() =>
              setPart(p === "meeting" ? {} : { part: p }, { replace: true })
            }
          >
            {p === "meeting" ? "Scouting meeting" : "Alliances"}
          </button>
        ))}
      </fieldset>
      {view === "meeting" ? (
        <div className="pl-meeting">
          <MeetingBoard e={edit} toolbar={lead ? toolbar : null} />
          {lists}
          <RankedList
            rows={ranked}
            editable={lead}
            drag={drag}
            moving={moving}
            onPick={pickTeam}
          />
        </div>
      ) : (
        <div className="pl-alliance-view">
          {lead && moving && (
            <Toolbar
              board={board}
              active={null}
              moving={moving}
              onStyle={() => undefined}
              onClear={() => undefined}
              onCancel={() => setMoving(null)}
            />
          )}
          <AllianceGrid e={edit} />
          <NextUp
            panels={panels}
            eventKey={eventKey}
            boardEmpty={readingOrder(board).length === 0}
          />
        </div>
      )}
    </>
  );
}

export function Playoffs() {
  const roles = useRoles();
  const { eventKey, eventReady } = useScoutData();
  const lead = roles.status === "ready" && isLead(roles.roles);
  return (
    <div className="picks playoffs">
      <h1>Playoffs</h1>
      <nav className="pick-tabs" aria-label="Picks sections">
        <Link className="btn" to="/picks">
          Pick list
        </Link>
        <Link className="btn" to="/picks?view=draft">
          Draft board
        </Link>
        <Link className="btn" to="/picks/playoffs" aria-current="page">
          Playoffs
        </Link>
      </nav>
      {eventKey === "" ? (
        <p className="secondary">
          {eventReady === false
            ? "Loading event."
            : "No event is set, so there is no board. Pick one in Settings."}
        </p>
      ) : (
        <Body key={eventKey} eventKey={eventKey} lead={lead} />
      )}
    </div>
  );
}
