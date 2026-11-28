import { type ReactNode, useMemo, useState } from "react";
import { Link } from "react-router";
import {
  acceptedTrades,
  applyTrades,
  type ScoutShifts,
  type ShiftRosterEntry,
  type ShiftTradeDoc,
  type Span,
} from "../scout/credit";
import { LeadTools, type Tool } from "./LeadTools";
import { type Delivery, DeliveryState, MyShifts } from "./MyShifts";
import { myBlocks } from "./mine";
import { RebuildTools } from "./RebuildTools";
import type { RebuildSummary } from "./rebuild";
import { ShiftGrid } from "./ShiftGrid";
import {
  type Cell,
  cellsBetween,
  generate,
  markUnavailable,
  paint,
} from "./schedule";
import "./shifts.css";
import { schedulePath } from "./paths";
import { Trades } from "./Trades";
import type { Load } from "./useShiftData";

export interface ShiftsViewProps {
  eventKey: string;
  auth: "loading" | "signed-out" | "signing-in" | "signed-in";
  uid: string | null;
  name: string;
  online: boolean;
  load: Load;
  fromCache: boolean;
  shifts: ScoutShifts | null;
  trades: ShiftTradeDoc[];
  played: number | null;
  qualCount: number;
  canEdit: boolean;
  deliveryOf(path: string): Delivery | undefined;
  onDismiss(id: string): void;
  onRequestTrade(block: Span, target: ShiftRosterEntry): void;
  onAnswerTrade(
    trade: ShiftTradeDoc,
    status: "accepted" | "declined" | "cancelled",
  ): void;
  onSave(next: ScoutShifts): void;
  onInputNames(names: string[], matchCount: number): void;
  onRebuild(from: number, names: string[]): Promise<RebuildSummary | null>;
  notice: string | null;
  pit?: ReactNode;
}

function Status({
  online,
  fromCache,
  load,
}: Pick<ShiftsViewProps, "online" | "fromCache" | "load">) {
  if (load === "failed") {
    return (
      <p className="notice" role="alert">
        The shifts could not be read. Check that you are signed in as a team
        member, then try again.
      </p>
    );
  }
  if (!online) {
    return (
      <p className="secondary">
        Offline. Showing the last copy saved on this device.
      </p>
    );
  }
  if (fromCache && load === "ready") {
    return <p className="secondary">Checking for newer shifts.</p>;
  }
  return null;
}

export function ShiftsView(props: ShiftsViewProps) {
  const { shifts, trades, uid, canEdit } = props;
  const [tool, setTool] = useState<Tool>({ kind: "color", color: "red" });
  const [note, setNote] = useState("");
  const [range, setRange] = useState(false);
  const [anchor, setAnchor] = useState<Cell | null>(null);
  const [tooMany, setTooMany] = useState(false);

  const effective = useMemo(
    () => (shifts ? applyTrades(shifts, acceptedTrades(trades)) : null),
    [shifts, trades],
  );
  const mine = useMemo(
    () =>
      effective && uid ? myBlocks(effective, trades, uid, props.played) : null,
    [effective, trades, uid, props.played],
  );
  const myTrades = uid
    ? trades.filter(
        (t) => t.id !== "" && (t.requesterUid === uid || t.targetUid === uid),
      )
    : [];

  const apply = (cells: Cell[]) => {
    if (!shifts) return;
    const next = paint(
      shifts,
      cells,
      tool.kind === "note" ? { text: note.trim() } : { color: tool.color },
    );
    setTooMany(next === null);
    if (next) props.onSave(next);
  };
  const onMark = (col: number, from: number, to: number, on: boolean) => {
    if (!shifts) return false;
    const next = markUnavailable(shifts, col, from, to, on);
    setTooMany(next === null);
    if (next) props.onSave(next);
    return next !== null;
  };
  const onCell = (cell: Cell) => {
    if (!range) return apply([cell]);
    if (!anchor) return setAnchor(cell);
    setAnchor(null);
    apply(cellsBetween(anchor, cell));
  };

  const header = (
    <>
      <h1>Scouting shifts</h1>
      <p className="secondary">{props.eventKey}</p>
    </>
  );

  if (props.eventKey === "") {
    return (
      <div className="page shifts">
        {header}
        <p>
          No event is selected. Set one in{" "}
          <Link to="/settings?s=event">Settings</Link>.
        </p>
      </div>
    );
  }
  if (props.auth === "signed-out" || props.auth === "signing-in") {
    return (
      <div className="page shifts">
        {header}
        <p>
          Sign in to see the shifts. You can do that in{" "}
          <Link to="/settings?s=account">Settings</Link>.
        </p>
      </div>
    );
  }

  const gridSave = props.deliveryOf(schedulePath(props.eventKey));
  const empty = !shifts || shifts.roster.length === 0;
  const waiting = props.load === "loading" || props.auth === "loading";
  const notStored = props.fromCache && !props.online;

  return (
    <div className="page shifts">
      {header}
      <div aria-live="polite" className="shift-notices">
        <Status
          online={props.online}
          fromCache={props.fromCache}
          load={props.load}
        />
        {props.notice && (
          <p className="notice" role="alert">
            {props.notice}
          </p>
        )}
        {tooMany && (
          <p className="notice" role="alert">
            A grid holds at most 4096 painted cells and notes. Clear some before
            painting more.
          </p>
        )}
      </div>

      {waiting && empty && <p className="secondary">Loading the shifts.</p>}

      {!waiting && empty && props.load !== "failed" && (
        <section className="shift-section" aria-labelledby="empty-h">
          <h2 id="empty-h">No schedule yet</h2>
          <p>
            {notStored
              ? "No copy of this event's shifts is saved on this device. Connect to load them."
              : canEdit
                ? "Use Input names to build one."
                : "Ask a strategy lead to build one."}
          </p>
        </section>
      )}

      {shifts && effective && !empty && uid && (
        <section className="shift-section" aria-labelledby="mine-h">
          <h2 id="mine-h">My shifts</h2>
          <MyShifts
            uid={uid}
            name={props.name}
            blocks={mine}
            shifts={effective}
            trades={trades}
            onRequestTrade={props.onRequestTrade}
          />
        </section>
      )}

      {myTrades.length > 0 && uid && (
        <section className="shift-section" aria-labelledby="trades-h">
          <h2 id="trades-h">Trades</h2>
          <Trades
            uid={uid}
            trades={myTrades}
            deliveryOf={props.deliveryOf}
            onDismiss={props.onDismiss}
            onAnswer={props.onAnswerTrade}
          />
        </section>
      )}

      {props.pit}

      {(!empty || canEdit) && !waiting && (
        <section className="shift-section" aria-labelledby="grid-h">
          <h2 id="grid-h">
            Schedule
            {shifts && !empty ? `, ${shifts.matchCount} qual matches` : ""}
          </h2>
          {canEdit && (
            <LeadTools
              shifts={shifts}
              qualCount={props.qualCount}
              tool={tool}
              onTool={(t) => {
                setTool(t);
                setAnchor(null);
              }}
              note={note}
              onNote={setNote}
              range={range}
              onRange={(on) => {
                setRange(on);
                setAnchor(null);
              }}
              onInputNames={props.onInputNames}
              onGenerate={() => shifts && props.onSave(generate(shifts))}
            />
          )}
          {canEdit && shifts && (
            <details className="mid-event">
              <summary>Mid-event changes</summary>
              <RebuildTools
                shifts={shifts}
                played={props.played}
                onMark={onMark}
                onRebuild={props.onRebuild}
              />
            </details>
          )}
          {gridSave && (
            <p className="delivery">
              <span className="secondary">Last change</span>
              <DeliveryState delivery={gridSave} onDismiss={props.onDismiss} />
            </p>
          )}
          {effective && !empty && (
            <ShiftGrid
              shifts={effective}
              mineUid={uid}
              anchor={anchor}
              onCell={canEdit ? onCell : undefined}
            />
          )}
        </section>
      )}
    </div>
  );
}
