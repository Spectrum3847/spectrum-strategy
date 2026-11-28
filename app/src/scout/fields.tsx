import { useEffect, useRef, useState } from "react";
import {
  choiceOptions,
  resolveStoredChoice,
  type ScoutField,
  selectedKeys,
  storedCounter,
  type Values,
} from "./config";
import type { ScheduledMatch } from "./schedule";
import { qualMatches } from "./schedule";

export interface FieldProps {
  field: ScoutField;
  values: Values;
  schedule: ScheduledMatch[];
  resetToken: number;
  onChange(code: string, value: unknown): void;
  onPatch(patch: Values): void;
}

function Chips({
  options,
  isOn,
  onPick,
  label,
}: {
  options: [string, string][];
  isOn(key: string): boolean;
  onPick(key: string): void;
  label: string;
}) {
  return (
    <fieldset className="chips">
      <legend className="sr-only">{label}</legend>
      {options.map(([key, text]) => (
        <button
          key={key}
          type="button"
          className="chip"
          aria-pressed={isOn(key)}
          onClick={() => onPick(key)}
        >
          {text}
        </button>
      ))}
    </fieldset>
  );
}

function Counter({
  field,
  value,
  onChange,
}: {
  field: ScoutField;
  value: unknown;
  onChange(v: number): void;
}) {
  const n = storedCounter(value) ?? 0;
  const steps = field.buttons ?? [1];
  const min = field.min ?? 0;
  const max = field.max;
  return (
    <div className="counter">
      <div className="counter-row">
        {steps.map((s) => (
          <button
            key={s}
            type="button"
            className="step-btn"
            aria-label={`${field.title} minus ${s}`}
            disabled={n - s < min}
            onClick={() => onChange(n - s)}
          >
            -{s}
          </button>
        ))}
      </div>
      <output className="counter-value" aria-label={`${field.title} value`}>
        {n}
      </output>
      <div className="counter-row">
        {steps.map((s) => (
          <button
            key={s}
            type="button"
            className="step-btn"
            aria-label={`${field.title} plus ${s}`}
            disabled={max !== null && n + s > max}
            onClick={() => onChange(n + s)}
          >
            +{s}
          </button>
        ))}
      </div>
    </div>
  );
}

const fmt = (s: number) => {
  const fixed = s.toFixed(1);
  return fixed.endsWith(".0") ? fixed.slice(0, -2) : fixed;
};

interface TrackerEvent {
  action: string;
  at: number;
  until?: number;
}

function Tracker({
  field,
  onPatch,
}: {
  field: ScoutField;
  onPatch(patch: Values): void;
}) {
  const [events, setEvents] = useState<TrackerEvent[]>([]);
  const [running, setRunning] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const started = useRef(0);
  const holding = useRef<Map<string, number>>(new Map());

  useEffect(() => {
    if (!running) return;
    const timer = setInterval(
      () => setElapsed((Date.now() - started.current) / 1000),
      100,
    );
    return () => clearInterval(timer);
  }, [running]);

  const commit = (next: TrackerEvent[]) => {
    setEvents(next);
    const patch: Values = {};
    for (const action of field.actions) {
      const mine = next.filter((e) => e.action === action.code);
      patch[`${field.code}_${action.code}_count`] = mine.length;
      patch[`${field.code}_${action.code}_times`] = mine
        .map((e) =>
          e.until === undefined ? fmt(e.at) : `${fmt(e.at)}-${fmt(e.until)}`,
        )
        .join(",");
    }
    onPatch(patch);
  };

  const now = () => (Date.now() - started.current) / 1000;
  const toggle = () => {
    if (running) {
      setRunning(false);
      return;
    }
    started.current = Date.now() - elapsed * 1000;
    setRunning(true);
  };

  return (
    <div className="tracker">
      <div className="tracker-bar">
        <button type="button" className="btn" onClick={toggle}>
          {running ? "Stop timer" : "Start timer"}
        </button>
        <output className="tracker-time">{fmt(elapsed)} s</output>
        <button
          type="button"
          className="btn"
          disabled={events.length === 0}
          onClick={() => commit(events.slice(0, -1))}
        >
          Undo
        </button>
      </div>
      <div className="chips">
        {field.actions.map((action) => {
          const count = events.filter((e) => e.action === action.code).length;
          const tap = field.trackerMode === "tap";
          return (
            <button
              key={action.code}
              type="button"
              className="chip"
              disabled={!running}
              onPointerDown={
                tap ? undefined : () => holding.current.set(action.code, now())
              }
              onPointerUp={
                tap
                  ? undefined
                  : () => {
                      const at = holding.current.get(action.code);
                      holding.current.delete(action.code);
                      if (at !== undefined) {
                        commit([
                          ...events,
                          { action: action.code, at, until: now() },
                        ]);
                      }
                    }
              }
              onClick={
                tap
                  ? () =>
                      commit([...events, { action: action.code, at: now() }])
                  : undefined
              }
            >
              {action.label} ({count})
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function FieldInput({
  field,
  values,
  schedule,
  resetToken,
  onChange,
  onPatch,
}: FieldProps) {
  const value = values[field.code];
  const set = (v: unknown) => onChange(field.code, v);
  switch (field.type) {
    case "text":
      return (
        <input
          aria-label={field.title}
          className="input"
          type="text"
          value={String(value ?? "")}
          onChange={(e) => set(e.target.value)}
        />
      );
    case "longText":
      return (
        <textarea
          aria-label={field.title}
          className="input"
          rows={4}
          value={String(value ?? "")}
          onChange={(e) => set(e.target.value)}
        />
      );
    case "number":
    case "tbaMatchNumber": {
      const n = Number.parseInt(String(value ?? ""), 10);
      const hasNumber = Number.isInteger(n);
      return (
        <div className="stepper">
          {field.type === "tbaMatchNumber" && (
            <button
              type="button"
              className="step-btn"
              aria-label={`${field.title} minus 1`}
              disabled={!hasNumber || n <= 1}
              onClick={() => set(String(n - 1))}
            >
              -1
            </button>
          )}
          <input
            aria-label={field.title}
            className="input"
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            onFocus={(e) => e.target.select()}
            value={String(value ?? "")}
            placeholder={
              field.min !== null && field.max !== null
                ? `${field.min} - ${field.max}`
                : ""
            }
            onChange={(e) => set(e.target.value.replace(/\D/g, ""))}
          />
          {field.type === "tbaMatchNumber" && (
            <button
              type="button"
              className="step-btn"
              aria-label={`${field.title} plus 1`}
              onClick={() => set(String(hasNumber ? n + 1 : 1))}
            >
              +1
            </button>
          )}
        </div>
      );
    }
    case "boolean":
      return (
        <Chips
          label={field.title}
          options={[
            ["no", "No"],
            ["yes", "Yes"],
          ]}
          isOn={(k) => (k === "yes") === (value === true)}
          onPick={(k) => set(k === "yes")}
        />
      );
    case "select": {
      const stored = resolveStoredChoice(field, value);
      const held = typeof value === "string" ? value : "";
      const options = choiceOptions(field, stored ? [stored] : []);
      if (options.length === 0)
        return <p className="secondary">No choices configured.</p>;
      const current = stored ?? held;
      if (options.length > 6) {
        return (
          <select
            aria-label={field.title}
            className="input"
            value={current}
            onChange={(e) => set(e.target.value)}
          >
            {current === "" && <option value="">Choose</option>}
            {options.map(([key, text]) => (
              <option key={key} value={key}>
                {text}
              </option>
            ))}
          </select>
        );
      }
      return (
        <Chips
          label={field.title}
          options={options}
          isOn={(k) => k === current}
          onPick={set}
        />
      );
    }
    case "checkboxSelect": {
      const picked = selectedKeys(value);
      const options = choiceOptions(field, picked);
      if (options.length === 0)
        return <p className="secondary">No choices configured.</p>;
      return (
        <Chips
          label={field.title}
          options={options}
          isOn={(k) => picked.includes(k)}
          onPick={(k) =>
            set(
              (picked.includes(k)
                ? picked.filter((p) => p !== k)
                : [...picked, k]
              ).join(","),
            )
          }
        />
      );
    }
    case "range": {
      const min = field.min ?? 0;
      const max = field.max ?? 100;
      const step = field.step ?? 1;
      const n =
        typeof value === "number" ? Math.min(max, Math.max(min, value)) : min;
      return (
        <div className="range">
          <input
            aria-label={field.title}
            type="range"
            min={min}
            max={max}
            step={step}
            value={n}
            onChange={(e) => set(Number(e.target.value))}
          />
          <output className="range-value">
            {n.toFixed(step < 1 ? 1 : 0)} / {max}
          </output>
        </div>
      );
    }
    case "counter":
    case "multiCounter":
      return <Counter field={field} value={value} onChange={set} />;
    case "tbaTeamAndRobot": {
      const match = qualMatches(schedule).find(
        (m) =>
          m.matchNumber ===
          Number.parseInt(String(values.matchNumber ?? ""), 10),
      );
      const held =
        typeof value === "object" && value !== null
          ? (value as Record<string, unknown>)
          : null;
      if (!match) {
        return (
          <input
            aria-label={field.title}
            className="input"
            type="text"
            inputMode="numeric"
            placeholder="Team number"
            value={held ? String(held.teamNumber ?? "") : ""}
            onChange={(e) => {
              const team = Number.parseInt(e.target.value, 10);
              set(
                Number.isInteger(team)
                  ? { teamNumber: team, robotPosition: "" }
                  : null,
              );
            }}
          />
        );
      }
      const robots: [string, string][] = [
        ...match.red.map((t, i): [string, string] => [
          `R${i + 1}`,
          `${t} (Red ${i + 1})`,
        ]),
        ...match.blue.map((t, i): [string, string] => [
          `B${i + 1}`,
          `${t} (Blue ${i + 1})`,
        ]),
      ];
      return (
        <Chips
          label={field.title}
          options={robots}
          isOn={(k) => held?.robotPosition === k}
          onPick={(k) => {
            const team = Number.parseInt(
              robots.find(([key]) => key === k)?.[1] ?? "",
              10,
            );
            set({ teamNumber: team, robotPosition: k });
          }}
        />
      );
    }
    case "actionTracker":
      return <Tracker key={resetToken} field={field} onPatch={onPatch} />;
    case "document":
      return (
        <p className="secondary">Attachments are not available in this form.</p>
      );
  }
}
