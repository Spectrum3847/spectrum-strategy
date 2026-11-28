import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { type Credit, rosterNames, type ScoutShifts } from "./credit";

export interface CreditBarProps {
  credit: Credit | null;
  shifts: ScoutShifts;
  standInUntil: number | null;
  matchKnown: boolean;
  onPick(who: { name: string; uid: string }): void;
  onClearStandIn(): void;
}

export function CreditBar(props: CreditBarProps) {
  const [open, setOpen] = useState(false);
  const { credit } = props;
  const asking = credit === null && props.matchKnown;
  return (
    <div className={asking ? "credit-bar ask" : "credit-bar"}>
      <p className="credit-line">
        {credit ? (
          <>
            <span className="credit-label">Scouting as</span>
            <strong className="credit-name">{credit.name}</strong>
            {credit.standIn && props.standInUntil !== null && (
              <span className="secondary">
                Stand-in until match {props.standInUntil}
              </span>
            )}
          </>
        ) : asking ? (
          <>
            <strong className="credit-name">Who is scouting?</strong>
            <span className="secondary">
              The schedule names nobody here for this match. Without a name the
              entry saves with no scout credited.
            </span>
          </>
        ) : (
          <span className="secondary">
            Enter the match number to see who is scouting.
          </span>
        )}
      </p>
      <button
        type="button"
        className="btn switch-btn"
        disabled={!props.matchKnown}
        onClick={() => setOpen(true)}
      >
        {asking ? "Choose a name" : "Not me? Switch"}
      </button>
      {open && (
        <SwitchSheet
          {...props}
          onClose={() => setOpen(false)}
          onPick={(who) => {
            props.onPick(who);
            setOpen(false);
          }}
          onClearStandIn={() => {
            props.onClearStandIn();
            setOpen(false);
          }}
        />
      )}
    </div>
  );
}

function SwitchSheet(props: CreditBarProps & { onClose(): void }) {
  const [typed, setTyped] = useState("");
  const close = useRef<HTMLButtonElement>(null);
  const { onClose } = props;
  useEffect(() => {
    close.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  const names = rosterNames(props.shifts);
  const typedName = typed.trim();
  return createPortal(
    <div
      className="switch-sheet"
      role="dialog"
      aria-modal="true"
      aria-labelledby="switch-h"
    >
      <div className="switch-inner">
        <h2 id="switch-h">Who is scouting?</h2>
        <p className="secondary">
          Credit stays with this person until the end of this shift, then goes
          back to the schedule.
        </p>
        <ul className="plain switch-list">
          {names.map((r) => (
            <li key={`${r.uid}:${r.name}`}>
              <button
                type="button"
                className="btn switch-name"
                aria-pressed={props.credit?.name === r.name}
                onClick={() => props.onPick({ name: r.name, uid: r.uid })}
              >
                {r.name}
              </button>
            </li>
          ))}
        </ul>
        <form
          className="actions"
          onSubmit={(e) => {
            e.preventDefault();
            if (typedName !== "") props.onPick({ name: typedName, uid: "" });
          }}
        >
          <input
            className="input"
            aria-label="Type a name"
            placeholder="Type a name"
            maxLength={128}
            value={typed}
            onChange={(e) => setTyped(e.target.value)}
          />
          <button
            type="submit"
            className="btn primary"
            disabled={typedName === ""}
          >
            Use this name
          </button>
        </form>
        {props.credit?.standIn && (
          <button type="button" className="btn" onClick={props.onClearStandIn}>
            Back to the schedule
          </button>
        )}
      </div>
      <div className="switch-foot">
        <button
          ref={close}
          type="button"
          className="btn big"
          onClick={props.onClose}
        >
          Cancel
        </button>
      </div>
    </div>,
    document.body,
  );
}
