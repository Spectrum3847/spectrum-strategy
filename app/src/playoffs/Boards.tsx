import type { ReactNode } from "react";
import { GripIcon } from "../picks/parts";
import {
  allianceColumns,
  allianceLabels,
  allianceRows,
  type CellRef,
  cellValue,
  extraRows,
  labelOf,
  maxCell,
  maxLabel,
  meetingColumns,
  meetingRows,
  type PlayoffBoard,
  type Source,
  styleOf,
} from "./board";
import type { CardColor } from "./derive";
import { type CellDrag, cellAttr, sameCell } from "./drag";

const cardText: Record<CardColor, string> = {
  red: "Red card",
  yellow: "Yellow card",
  unknown: "Card",
};

export interface BoardEdit {
  readOnly: boolean;
  board: PlayoffBoard;
  drag: CellDrag;
  moving: Source | null;
  onText(ref: CellRef, text: string): void;
  onLabel(column: number, text: string): void;
  onFocus(ref: CellRef): void;
  onHandle(ref: CellRef): void;
  cards: Map<number, CardColor>;
}

const teamIn = (text: string) =>
  /^\d{1,5}$/.test(text.trim()) ? Number(text.trim()) : null;

export function whereLabel(board: PlayoffBoard, ref: CellRef): string {
  return ref.grid === "meeting"
    ? `${labelOf(board, ref.column)} row ${ref.row + 1}`
    : `Alliance ${ref.row + 1} ${allianceLabels[ref.column] ?? ""}`.trim();
}

const heldText = (moving: Source) =>
  moving.kind === "team" ? String(moving.team) : "the held cell";

function Cell({
  ref_,
  e,
  focusCell,
}: {
  ref_: CellRef;
  e: BoardEdit;
  focusCell: boolean;
}) {
  const text = cellValue(e.board, ref_);
  const where = whereLabel(e.board, ref_);
  const team = teamIn(text);
  const card =
    ref_.grid === "alliance" && team !== null ? e.cards.get(team) : undefined;
  const style =
    ref_.grid === "meeting" ? styleOf(e.board, ref_.row, ref_.column) : null;
  const picked = e.moving?.kind === "cell" && sameCell(e.moving, ref_);
  const draggingThis =
    e.drag.dragging?.kind === "cell" && sameCell(e.drag.dragging, ref_);
  const over = sameCell(e.drag.over, ref_);
  const filled = text.trim() !== "";
  const source: Source = { kind: "cell", ...ref_ };
  const id = cellAttr(ref_);
  const placing = e.moving !== null && !picked;
  const handlers = filled && !e.readOnly ? e.drag.handlers(source, id) : {};
  return (
    <div
      className="pl-cell"
      data-cell={id}
      data-over={over ? "true" : undefined}
      data-picked={picked || draggingThis ? "true" : undefined}
      data-highlight={style?.highlighted ? "true" : undefined}
      data-card={card}
    >
      <button
        type="button"
        className="pl-handle"
        data-handle={id}
        aria-label={
          picked
            ? `Put down ${text}`
            : placing && e.moving
              ? `Place ${heldText(e.moving)} in ${where}`
              : filled
                ? `Move ${text} from ${where}`
                : `${where} is empty`
        }
        aria-pressed={picked}
        disabled={e.readOnly || (!filled && !placing)}
        onClick={() => {
          if (e.drag.wasDrag()) return;
          e.onHandle(ref_);
        }}
        {...handlers}
      >
        <GripIcon />
      </button>
      <div className="pl-field">
        <input
          className="pl-input"
          type="text"
          inputMode="text"
          aria-label={where}
          value={text}
          maxLength={maxCell}
          readOnly={e.readOnly}
          autoComplete="off"
          data-italic={style?.italic ? "true" : undefined}
          onChange={(ev) => e.onText(ref_, ev.target.value)}
          onFocus={() => focusCell && e.onFocus(ref_)}
        />
        {card && <span className="pl-card">{cardText[card]}</span>}
      </div>
    </div>
  );
}

export function MeetingBoard({
  e,
  toolbar,
}: {
  e: BoardEdit;
  toolbar: ReactNode;
}) {
  const columns = Array.from({ length: meetingColumns }, (_, c) => c);
  const rows = Array.from({ length: meetingRows + extraRows }, (_, r) => r);
  const last = meetingColumns - 1;
  return (
    <section className="pl-section" aria-labelledby="pl-meeting-h">
      <h2 id="pl-meeting-h">Sorting board</h2>
      <p className="secondary">
        {e.readOnly
          ? "Best to worst, left to right."
          : "Best to worst, left to right. Rename a column by typing over its name. Type a team, or drag one from the ranked list. To move without dragging, tap a team's grip, then tap where it goes."}
      </p>
      {toolbar}
      <div className="pl-scroll" tabIndex={-1}>
        <table className="pl-table">
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c} scope="col">
                  <input
                    className="pl-input pl-label"
                    type="text"
                    aria-label={`Column ${c + 1} name`}
                    value={labelOf(e.board, c)}
                    maxLength={maxLabel}
                    readOnly={e.readOnly}
                    autoComplete="off"
                    onChange={(ev) => e.onLabel(c, ev.target.value)}
                  />
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r}>
                {columns.map((c) =>
                  r >= meetingRows && c !== last ? (
                    <td key={c} className="pl-void" />
                  ) : (
                    <td key={c}>
                      <Cell
                        ref_={{ grid: "meeting", row: r, column: c }}
                        e={e}
                        focusCell
                      />
                    </td>
                  ),
                )}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export function AllianceGrid({ e }: { e: BoardEdit }) {
  const columns = Array.from({ length: allianceColumns }, (_, c) => c);
  const rows = Array.from({ length: allianceRows }, (_, r) => r);
  return (
    <section className="pl-section" aria-labelledby="pl-alliance-h">
      <h2 id="pl-alliance-h">Alliances</h2>
      <p className="secondary">
        {e.readOnly
          ? "A team placed here leaves the next-up list."
          : "Type a team into an alliance, or drag one in. A team placed here leaves the next-up list."}
      </p>
      <div className="pl-scroll" tabIndex={-1}>
        <table className="pl-table pl-alliances">
          <thead>
            <tr>
              <th scope="col">Alliance</th>
              {columns.map((c) => (
                <th key={c} scope="col">
                  {allianceLabels[c]}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r}>
                <th scope="row">{r + 1}</th>
                {columns.map((c) => (
                  <td key={c}>
                    <Cell
                      ref_={{ grid: "alliance", row: r, column: c }}
                      e={e}
                      focusCell={false}
                    />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
