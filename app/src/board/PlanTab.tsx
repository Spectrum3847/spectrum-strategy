import { type ReactElement, useEffect, useId, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { parseMatchKey } from "../data/matchKey";
import { BoardCanvas } from "./Canvas";
import { canMoveSide, type Robot } from "./edit";
import { exportBoard, pictureOf } from "./exportImage";
import { bundled, fieldFor } from "./field";
import {
  CheckIcon,
  CollapseIcon,
  EraserIcon,
  ExpandIcon,
  PenIcon,
  RedoIcon,
  RobotIcon,
  ShareIcon,
  TextIcon,
  UndoIcon,
} from "./icons";
import { maxPracticeTeams } from "./list";
import {
  type Marker,
  type Phase,
  phaseLabels,
  phases,
  type Tool,
} from "./model";
import type { DeliveryKind } from "./sync";
import { useBoard } from "./useBoard";
import "./board.css";

const toolInfo: { tool: Tool; label: string; hint: string }[] = [
  {
    tool: "draw",
    label: "Draw",
    hint: "Draw: drag on the board to sketch a path.",
  },
  {
    tool: "robot",
    label: "Robot",
    hint: "Robot: tap the board to place the chosen robot. Drag a robot to move it.",
  },
  {
    tool: "text",
    label: "Text",
    hint: "Text: tap to add or edit a label, drag to move it.",
  },
  {
    tool: "delete",
    label: "Erase",
    hint: "Erase: touch one line or robot to remove just that one.",
  },
];

const toolIcon: Record<Tool, () => ReactElement> = {
  draw: PenIcon,
  robot: RobotIcon,
  text: TextIcon,
  delete: EraserIcon,
};

const stateColor: Record<DeliveryKind, string> = {
  none: "none",
  failed: "refused",
  device: "on-device",
  waiting: "on-device",
  sending: "sending",
  database: "in-database",
  copy: "on-device",
  refused: "refused",
};

const timeOf = (ms: number) =>
  new Date(ms).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

export interface PlanProps {
  eventKey: string;
  matchKey: string;
  red: number[];
  blue: number[];
  ours: "red" | "blue" | null;
  label: string;
}

export default function PlanTab(props: PlanProps) {
  const ref = parseMatchKey(props.matchKey);
  if (props.eventKey === "") {
    return <p className="secondary">No event is set. Pick one in Settings.</p>;
  }
  if (ref?.level !== "qm") {
    return (
      <p className="secondary">
        Boards are kept per qualification match number, so a playoff match has
        no board here.
      </p>
    );
  }
  return <Board {...props} matchNumber={ref.number} />;
}

export interface BoardProps extends Omit<PlanProps, "matchKey"> {
  matchNumber: number;
  id?: string;
  localKey?: string;
  practice?: boolean;
  canMoveSides?: boolean;
}

export function Board({
  eventKey,
  red,
  blue,
  ours,
  label,
  matchNumber,
  id,
  localKey,
  practice,
  canMoveSides,
}: BoardProps) {
  const seed: Robot[] = [
    ...red.map((team) => ({ team, side: "red" as const })),
    ...blue.map((team) => ({ team, side: "blue" as const })),
  ];
  const { controller, state, delivery, failed } = useBoard({
    eventKey,
    matchNumber,
    alliance: ours === "blue" ? "Blue" : "Red",
    robots: seed,
    label: `Strategy board for ${label}`,
    ...(id !== undefined && { id }),
    ...(localKey !== undefined && { localKey }),
    ...(practice !== undefined && { practice }),
  });
  const robots = state.robots;
  const [askClear, setAskClear] = useState(false);
  const [showSides, setShowSides] = useState(false);
  const sidesId = useId();
  const [full, setFull] = useState(
    () => window.matchMedia?.("(max-width: 599px)").matches ?? false,
  );
  const hintId = useId();
  const noteId = useId();
  const exitRef = useRef<HTMLButtonElement>(null);
  const enterRef = useRef<HTMLButtonElement>(null);
  const wasFull = useRef(false);
  const [exporting, setExporting] = useState(false);
  const [exported, setExported] = useState("");

  useEffect(() => {
    if (!full) return;
    const root = document.getElementById("root");
    root?.setAttribute("inert", "");
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !e.defaultPrevented) setFull(false);
    };
    document.addEventListener("keydown", onKey);
    return () => {
      root?.removeAttribute("inert");
      document.body.style.overflow = overflow;
      document.removeEventListener("keydown", onKey);
    };
  }, [full]);

  useEffect(() => {
    if (!askClear) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape" && !e.defaultPrevented) {
        e.preventDefault();
        setAskClear(false);
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [askClear]);

  useEffect(() => {
    if (full) exitRef.current?.focus();
    else if (wasFull.current) enterRef.current?.focus();
    wasFull.current = full;
  }, [full]);

  const field = fieldFor(bundled, state.session.selectedFieldId);
  if (!field) {
    return <p className="notice">No field map is bundled with this app.</p>;
  }
  if (!state.ready) {
    return (
      <p className="secondary" role="status">
        Loading the board
      </p>
    );
  }
  if (id !== undefined && !state.hasBoard) {
    return (
      <p className="notice" role="status">
        This board is not on this device or in the database. It may have been
        deleted.
      </p>
    );
  }

  const sideOf = (m: Marker) =>
    robots.find((r) => r.team === m.team)?.side ??
    (m.alliance === "Blue" ? "blue" : "red");
  const exportImage = async () => {
    setExporting(true);
    setExported("");
    try {
      const picture = pictureOf(
        state.session,
        state.phase,
        field.aspect,
        sideOf,
      );
      const { delivery: how, fileName } = await exportBoard(
        picture,
        field.image,
      );
      setExported(
        how === "shared"
          ? "Shared the board image."
          : how === "downloaded"
            ? `Downloaded ${fileName}.`
            : "",
      );
    } catch {
      setExported("Could not make the image. Try again.");
    } finally {
      setExporting(false);
    }
  };

  const canSetSides = canMoveSides === true && state.practice;
  const info = toolInfo.find((t) => t.tool === state.tool) ?? toolInfo[0];
  const placed = new Set(
    state.session.markers[state.phase].flatMap((m) =>
      m.team === null ? [] : [m.team],
    ),
  );
  const alert =
    delivery.kind === "failed" || delivery.kind === "refused"
      ? "alert"
      : undefined;

  const body = (
    <section
      className="board"
      data-full={full}
      aria-label="Strategy board"
      {...(full ? { role: "dialog", "aria-modal": true } : {})}
    >
      <div className="board-bar">
        <fieldset className="board-group">
          <legend className="sr-only">Phase</legend>
          {phases.map((p: Phase) => (
            <button
              key={p}
              type="button"
              className="chip"
              aria-pressed={state.phase === p}
              onClick={() => controller.selectPhase(p)}
            >
              {phaseLabels[p]}
            </button>
          ))}
        </fieldset>
        <fieldset className="board-group">
          <legend className="sr-only">Tool</legend>
          {toolInfo.map(({ tool, label: name }) => {
            const Icon = toolIcon[tool];
            return (
              <button
                key={tool}
                type="button"
                className="chip"
                aria-pressed={state.tool === tool}
                onClick={() => controller.selectTool(tool)}
              >
                <Icon />
                {name}
              </button>
            );
          })}
        </fieldset>
        <fieldset className="board-group">
          <legend className="sr-only">Changes</legend>
          <button
            type="button"
            className="board-tool"
            aria-label="Undo"
            disabled={!state.canUndo}
            onClick={() => controller.undo()}
          >
            <UndoIcon />
          </button>
          <button
            type="button"
            className="board-tool"
            aria-label="Redo"
            disabled={!state.canRedo}
            onClick={() => controller.redo()}
          >
            <RedoIcon />
          </button>
          <button
            type="button"
            className="btn"
            onClick={() => controller.clearPhase()}
          >
            Clear {phaseLabels[state.phase]}
          </button>
          <button
            type="button"
            className="btn"
            aria-expanded={askClear}
            onClick={() => setAskClear((a) => !a)}
          >
            Clear all phases
          </button>
        </fieldset>
        <button
          type="button"
          className="btn"
          disabled={exporting}
          onClick={exportImage}
        >
          <ShareIcon />
          Export image
        </button>
        {canSetSides && (
          <button
            type="button"
            className="btn"
            aria-expanded={showSides}
            aria-controls={sidesId}
            onClick={() => setShowSides((s) => !s)}
          >
            Team sides
          </button>
        )}
        {full ? (
          <button
            ref={exitRef}
            type="button"
            className="btn board-full-toggle"
            onClick={() => setFull(false)}
          >
            <CollapseIcon />
            Exit full screen
          </button>
        ) : (
          <button
            ref={enterRef}
            type="button"
            className="btn board-full-toggle"
            onClick={() => setFull(true)}
          >
            <ExpandIcon />
            Full screen
          </button>
        )}
      </div>

      {canSetSides && showSides && (
        <div id={sidesId} className="board-sides">
          <p className="secondary">
            Move a team to the other side. Each side holds up to{" "}
            {maxPracticeTeams} teams.
          </p>
          <ul>
            {[...state.session.teamNumbers]
              .sort((a, b) => a - b)
              .map((team) => {
                const side = robots.find((r) => r.team === team)?.side ?? "red";
                const other = side === "red" ? "blue" : "red";
                return (
                  <li key={team} data-side={side}>
                    <span className="board-side" aria-hidden="true">
                      {side === "red" ? "R" : "B"}
                    </span>
                    <strong>{team}</strong>
                    <span className="secondary">
                      {side === "red" ? "Red" : "Blue"}
                    </span>
                    <button
                      type="button"
                      className="btn"
                      disabled={!canMoveSide(state.session, team)}
                      onClick={() => controller.moveTeamSide(team)}
                    >
                      Move {team} to {other}
                    </button>
                  </li>
                );
              })}
          </ul>
        </div>
      )}

      {askClear && (
        <div className="notice board-clear" role="alert">
          <p>
            Clear the drawings, robots, labels and notes of all three phases?
            Undo brings each phase back.
          </p>
          <div className="actions">
            <button
              type="button"
              className="btn"
              onClick={() => {
                controller.clearAll();
                setAskClear(false);
              }}
            >
              Clear all phases
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => setAskClear(false)}
            >
              Keep the board
            </button>
          </div>
        </div>
      )}

      {state.tool === "robot" && (
        <fieldset className="board-tray">
          <legend className="sr-only">Robots</legend>
          {robots.map((r) => {
            const on = placed.has(r.team);
            return (
              <button
                key={r.team}
                type="button"
                className="board-robot"
                data-side={r.side}
                data-placed={on}
                aria-pressed={state.team === r.team}
                aria-label={`${r.team}, ${r.side}${on ? ", on the field" : ""}`}
                onClick={() => controller.selectTeam(r.team)}
              >
                <span className="board-side" aria-hidden="true">
                  {r.side === "red" ? "R" : "B"}
                </span>
                {r.team}
                {on && <CheckIcon />}
              </button>
            );
          })}
          <button
            type="button"
            className="btn"
            onClick={() => controller.placeAll()}
          >
            Place all six
          </button>
        </fieldset>
      )}

      <p id={hintId} className="secondary">
        {info?.hint} Two fingers zoom and move the view.
      </p>

      <BoardCanvas
        field={field}
        state={state}
        robots={robots}
        controller={controller}
        full={full}
        describedBy={hintId}
      />

      <div className="board-status">
        {state.conflict && (
          <div className="notice" role="alert">
            <p>
              <strong>Another device saved a newer version.</strong>{" "}
              {state.conflict.authorDisplayName || "A teammate"} saved it at{" "}
              {timeOf(state.conflict.updatedMs)}. This device has changes the
              database does not have yet.
            </p>
            <div className="actions">
              <button
                type="button"
                className="btn"
                onClick={() => controller.loadTheirs()}
              >
                Use their version
              </button>
              <button
                type="button"
                className="btn"
                onClick={() => controller.keepMine()}
              >
                Keep mine
              </button>
            </div>
            <p>
              Their version drops this device's changes. Keeping mine replaces
              theirs.
            </p>
          </div>
        )}
        <p
          className="state board-state"
          data-state={stateColor[delivery.kind]}
          role={alert}
        >
          {delivery.text}
        </p>
        <p className="secondary" role="status">
          {exported}
        </p>
        {failed && (
          <p className="secondary" role="status">
            Could not read the database. Another device's changes may be
            missing.
          </p>
        )}
      </div>

      {!full && (
        <label className="board-note" htmlFor={noteId}>
          <span className="field-name">
            Notes for {phaseLabels[state.phase]}
          </span>
          <textarea
            id={noteId}
            className="input"
            rows={2}
            maxLength={2000}
            value={state.session.notes[state.phase]}
            onChange={(e) => controller.setNote(e.target.value)}
          />
        </label>
      )}
    </section>
  );

  return full ? createPortal(body, document.body) : body;
}
