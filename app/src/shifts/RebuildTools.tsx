import { type FormEvent, useState } from "react";
import type { ScoutShifts } from "../scout/credit";
import { rangeText } from "./mine";
import { nextBlockStart, type RebuildSummary, rebuildStart } from "./rebuild";
import { parseNames } from "./roster";
import { hasRotation } from "./schedule";

export interface RebuildToolsProps {
  shifts: ScoutShifts;
  played: number | null;
  onMark(col: number, from: number, to: number, on: boolean): boolean;
  onRebuild(from: number, names: string[]): Promise<RebuildSummary | null>;
}

const matchNumber = (text: string, last: number): number | null => {
  const n = Number.parseInt(text, 10);
  return Number.isInteger(n) && n >= 1 && n <= last ? n : null;
};

const nameList = (names: string[]) =>
  names.length <= 8
    ? names.join(", ")
    : `${names.slice(0, 8).join(", ")} and ${names.length - 8} more`;

function Unavailable({
  shifts,
  onMark,
}: Pick<RebuildToolsProps, "shifts" | "onMark">) {
  const [col, setCol] = useState("0");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [message, setMessage] = useState<{ text: string; error: boolean }>();
  const run = (on: boolean) => {
    const a = matchNumber(from, shifts.matchCount);
    const b = matchNumber(to === "" ? from : to, shifts.matchCount);
    if (a === null || b === null || b < a) {
      return setMessage({
        text: `Enter match numbers from 1 to ${shifts.matchCount}, the first no later than the last.`,
        error: true,
      });
    }
    const index = Number.parseInt(col, 10);
    if (!onMark(index, a, b, on)) {
      return setMessage({
        text: "The grid has too many painted cells to add this. Clear some marks first.",
        error: true,
      });
    }
    const who = shifts.roster[index]?.name || `Scout ${index + 1}`;
    const span = rangeText({ startMatch: a, endMatch: b });
    setMessage({
      text: on
        ? `${who} is unavailable for ${span}.`
        : `Cleared the unavailable marks for ${who}, ${span}.`,
      error: false,
    });
  };
  const submit = (e: FormEvent) => {
    e.preventDefault();
    run(true);
  };
  return (
    <form className="rebuild-form" onSubmit={submit}>
      <h3 className="field-name">Mark a scout unavailable</h3>
      <p className="secondary">
        Lunch, inspection, drive team. The matches turn red on the grid, and a
        rebuild keeps that scout off them. Tapping cells with Red does the same.
      </p>
      <label className="label" htmlFor="unavail-scout">
        Scout
      </label>
      <select
        id="unavail-scout"
        className="input"
        value={col}
        onChange={(e) => setCol(e.target.value)}
      >
        {shifts.roster.map((r, i) => (
          // biome-ignore lint/suspicious/noArrayIndexKey: columns are positional
          <option key={i} value={i}>
            {r.name === "" ? `(no name ${i + 1})` : r.name}
          </option>
        ))}
      </select>
      <div className="range-row">
        <div>
          <label className="label" htmlFor="unavail-from">
            From match
          </label>
          <input
            id="unavail-from"
            className="input"
            inputMode="numeric"
            value={from}
            onChange={(e) => setFrom(e.target.value)}
          />
        </div>
        <div>
          <label className="label" htmlFor="unavail-to">
            To match
          </label>
          <input
            id="unavail-to"
            className="input"
            inputMode="numeric"
            placeholder={from}
            value={to}
            onChange={(e) => setTo(e.target.value)}
          />
        </div>
      </div>
      <div className="actions">
        <button type="submit" className="btn">
          Mark unavailable
        </button>
        <button type="button" className="btn" onClick={() => run(false)}>
          Clear unavailable
        </button>
      </div>
      {message && (
        <p
          className={message.error ? "notice" : "secondary"}
          role={message.error ? "alert" : "status"}
        >
          {message.text}
        </p>
      )}
    </form>
  );
}

function Rebuild({
  shifts,
  played,
  onRebuild,
}: Pick<RebuildToolsProps, "shifts" | "played" | "onRebuild">) {
  const [typed, setTyped] = useState<string | null>(null);
  const [added, setAdded] = useState("");
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [summary, setSummary] = useState<RebuildSummary | null>(null);
  const fromText = typed ?? String(nextBlockStart(played));
  const from = matchNumber(fromText, shifts.matchCount);
  const names = parseNames(added);

  const change = (apply: () => void) => {
    apply();
    setConfirm(false);
    setError(null);
  };
  const ask = (e: FormEvent) => {
    e.preventDefault();
    setSummary(null);
    if (from === null) {
      return setError(
        `Enter a match from 1 to ${shifts.matchCount}. With every match started there is nothing to rebuild.`,
      );
    }
    if (!confirm) return setConfirm(true);
    setConfirm(false);
    setBusy(true);
    onRebuild(from, names)
      .then(setSummary)
      .finally(() => setBusy(false));
  };

  const start = from === null ? null : rebuildStart(shifts, from);
  return (
    <form className="rebuild-form" onSubmit={ask}>
      <h3 className="field-name">Rebuild from next shift</h3>
      <p className="secondary">
        Shifts that started before the match below stay as they are. The rest is
        regenerated with fairness and stations carried over. Red cells keep
        scouts off their matches.
      </p>
      <label className="label" htmlFor="rebuild-from">
        Rebuild from match
      </label>
      <input
        id="rebuild-from"
        className="input"
        inputMode="numeric"
        value={fromText}
        onChange={(e) => change(() => setTyped(e.target.value))}
      />
      <label className="label" htmlFor="rebuild-add">
        Add scouts (optional, one name per line)
      </label>
      <textarea
        id="rebuild-add"
        className="input"
        rows={3}
        value={added}
        onChange={(e) => change(() => setAdded(e.target.value))}
      />
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      {confirm && from !== null && start !== null && (
        <p id="rebuild-warning" className="secondary">
          {start > shifts.matchCount
            ? "Every shift has started, so nothing changes."
            : `Keeps every shift that started before Q${from}${start > from ? ` and the ones running through Q${start - 1}` : ""}. Replaces everyone's shifts from Q${start}.`}
          {names.length > 0 &&
            ` Adds ${names.length === 1 ? "1 scout" : `${names.length} scouts`}.`}{" "}
          Red cells and notes stay.
        </p>
      )}
      <div className="actions">
        <button
          type="submit"
          className="btn primary"
          disabled={busy}
          aria-describedby={confirm ? "rebuild-warning" : undefined}
        >
          {confirm ? "Replace the rest" : "Rebuild from next shift"}
        </button>
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
      {summary && (
        <div role="status" className="rebuild-summary">
          <p>
            Rebuilt from Q{summary.from}. Kept {summary.keptShifts} shifts and
            planned {summary.newShifts} new ones.{" "}
            {summary.changed.length === 0
              ? "No scout's shifts changed."
              : `${summary.changed.length === 1 ? "1 scout has" : `${summary.changed.length} scouts have`} different shifts: ${nameList(summary.changed)}.`}
          </p>
          {summary.warnings.length > 0 && (
            <div className="notice">
              <p>Check these:</p>
              <ul>
                {summary.warnings.map((w) => (
                  <li key={w}>{w}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}
    </form>
  );
}

export function RebuildTools(props: RebuildToolsProps) {
  const { shifts } = props;
  if (shifts.roster.length === 0 || shifts.matchCount === 0) return null;
  return (
    <div className="rebuild">
      <Unavailable shifts={shifts} onMark={props.onMark} />
      {hasRotation(shifts) && (
        <Rebuild
          shifts={shifts}
          played={props.played}
          onRebuild={props.onRebuild}
        />
      )}
    </div>
  );
}
