import { type FormEvent, useState } from "react";
import type { ScoutShifts } from "../scout/credit";
import { maxMatchCount } from "./generate";
import { parseNames } from "./roster";
import { type CellColor, cellColors, hasRotation, maxRoster } from "./schedule";

export type Tool =
  | { kind: "color"; color: CellColor | null }
  | { kind: "note" };

export interface LeadToolsProps {
  shifts: ScoutShifts | null;
  qualCount: number;
  tool: Tool;
  onTool(tool: Tool): void;
  note: string;
  onNote(text: string): void;
  range: boolean;
  onRange(on: boolean): void;
  onInputNames(names: string[], matchCount: number): void;
  onGenerate(): void;
}

const colorLabel: Record<CellColor, string> = {
  green: "Green",
  white: "White",
  grey: "Grey",
  red: "Red",
};

function NamesForm({
  shifts,
  qualCount,
  onSubmit,
  onClose,
}: {
  shifts: ScoutShifts | null;
  qualCount: number;
  onSubmit(names: string[], matchCount: number): void;
  onClose(): void;
}) {
  const [names, setNames] = useState(
    shifts?.roster.map((r) => r.name).join("\n") ?? "",
  );
  const start = shifts?.matchCount || qualCount;
  const [count, setCount] = useState(start > 0 ? String(start) : "");
  const [error, setError] = useState<string | null>(null);
  const replaces = shifts !== null && shifts.roster.length > 0;
  const submit = (e: FormEvent) => {
    e.preventDefault();
    const list = parseNames(names);
    const matchCount = Number.parseInt(count, 10);
    if (list.length === 0) return setError("Enter at least one name.");
    if (list.length > maxRoster) {
      return setError(`The roster can hold ${maxRoster} names at most.`);
    }
    if (!Number.isInteger(matchCount) || matchCount <= 0) {
      return setError("Enter how many qualification matches there are.");
    }
    if (matchCount > maxMatchCount) {
      return setError(`The match count cannot be more than ${maxMatchCount}.`);
    }
    onSubmit(list, matchCount);
  };
  return (
    <form className="names-form" onSubmit={submit}>
      <label className="field-name" htmlFor="shift-names">
        Scout names
      </label>
      <p className="secondary">
        One name per line, or paste a list separated by commas or tabs. A name
        links to an account when it matches the account name exactly.
      </p>
      <textarea
        id="shift-names"
        className="input"
        rows={8}
        value={names}
        onChange={(e) => setNames(e.target.value)}
      />
      <label className="field-name" htmlFor="shift-count">
        Qualification matches
      </label>
      <input
        id="shift-count"
        className="input"
        inputMode="numeric"
        value={count}
        onChange={(e) => setCount(e.target.value)}
      />
      {replaces && (
        <p className="secondary">
          This replaces the current grid, including every painted cell and note.
        </p>
      )}
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      <div className="actions">
        <button type="submit" className="btn primary">
          {replaces ? "Replace grid" : "Save names"}
        </button>
        <button type="button" className="btn" onClick={onClose}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export function LeadTools(props: LeadToolsProps) {
  const { shifts, tool, range } = props;
  const [names, setNames] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const generated = shifts !== null && hasRotation(shifts);
  const generate = () => {
    if (generated && !confirm) return setConfirm(true);
    setConfirm(false);
    props.onGenerate();
  };
  const isColor = (c: CellColor | null) =>
    tool.kind === "color" && tool.color === c;
  return (
    <div className="lead-tools">
      <div className="actions">
        <button
          type="button"
          className="btn"
          aria-expanded={names}
          onClick={() => setNames(!names)}
        >
          Input names
        </button>
        {shifts && shifts.roster.length > 0 && (
          <button
            type="button"
            className="btn primary"
            onClick={generate}
            aria-describedby={confirm ? "generate-warning" : undefined}
          >
            {confirm ? "Replace shifts" : "Generate scouting schedule"}
          </button>
        )}
        {confirm && (
          <button
            type="button"
            className="btn"
            onClick={() => setConfirm(false)}
          >
            Keep current shifts
          </button>
        )}
      </div>
      {confirm && (
        <p id="generate-warning" className="secondary">
          This replaces everyone's shifts. Red cells and notes stay.
        </p>
      )}
      {names && (
        <NamesForm
          shifts={shifts}
          qualCount={props.qualCount}
          onSubmit={(list, matchCount) => {
            setNames(false);
            props.onInputNames(list, matchCount);
          }}
          onClose={() => setNames(false)}
        />
      )}
      {shifts && shifts.roster.length > 0 && (
        <fieldset className="paint">
          <legend className="label">Tap cells to paint them</legend>
          <div className="paint-chips">
            {cellColors.map((c) => (
              <button
                key={c}
                type="button"
                className="chip"
                aria-pressed={isColor(c)}
                onClick={() => props.onTool({ kind: "color", color: c })}
              >
                {colorLabel[c]}
              </button>
            ))}
            <button
              type="button"
              className="chip"
              aria-pressed={isColor(null)}
              onClick={() => props.onTool({ kind: "color", color: null })}
            >
              Clear color
            </button>
            <button
              type="button"
              className="chip"
              aria-pressed={tool.kind === "note"}
              onClick={() => props.onTool({ kind: "note" })}
            >
              Note
            </button>
            <button
              type="button"
              className="chip"
              aria-pressed={range}
              onClick={() => props.onRange(!range)}
            >
              Range
            </button>
          </div>
          {tool.kind === "note" && (
            <>
              <label className="field-name" htmlFor="shift-note">
                Note text (empty clears the note)
              </label>
              <input
                id="shift-note"
                className="input"
                value={props.note}
                onChange={(e) => props.onNote(e.target.value)}
              />
            </>
          )}
          {range && (
            <p className="secondary">
              Tap one corner, then the opposite corner, to paint the block
              between them.
            </p>
          )}
        </fieldset>
      )}
    </div>
  );
}
