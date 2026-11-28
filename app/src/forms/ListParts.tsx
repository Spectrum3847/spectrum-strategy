import { useState } from "react";
import type { TbaStatus } from "../data/useTbaEvent";
import { parseTeamParam } from "./kinds";
import "./forms.css";

export function OpenTeam(props: { onOpen(team: number): void }) {
  const [typed, setTyped] = useState("");
  const team = parseTeamParam(typed);
  return (
    <form
      className="panel"
      onSubmit={(e) => {
        e.preventDefault();
        if (team !== null) props.onOpen(team);
      }}
    >
      <label className="field-name" htmlFor="open-team">
        Open a team by number
      </label>
      <div className="open-row">
        <input
          id="open-team"
          className="input"
          type="text"
          inputMode="numeric"
          pattern="[0-9]*"
          value={typed}
          onChange={(e) => setTyped(e.target.value.replace(/\D/g, ""))}
        />
        <button type="submit" className="btn" disabled={team === null}>
          Open
        </button>
      </div>
    </form>
  );
}

export function ListHead(props: {
  title: string;
  eventKey: string;
  online: boolean;
  unsent: number;
}) {
  return (
    <header className="forms-head">
      <h1>{props.title}</h1>
      <p className="status-line secondary" aria-live="polite">
        <span>{props.eventKey || "No event"}</span>
        <span>{props.online ? "Online" : "Offline"}</span>
        {props.unsent > 0 && <span>{props.unsent} unsent</span>}
      </p>
    </header>
  );
}

export function FilterChips<T extends string>(props: {
  label: string;
  options: { key: T; text: string }[];
  value: T;
  onPick(key: T): void;
}) {
  return (
    <fieldset className="chips">
      <legend className="sr-only">{props.label}</legend>
      {props.options.map((o) => (
        <button
          key={o.key}
          type="button"
          className="chip"
          aria-pressed={props.value === o.key}
          onClick={() => props.onPick(o.key)}
        >
          {o.text}
        </button>
      ))}
    </fieldset>
  );
}

export function teamsMessage(eventKey: string, status: TbaStatus): string {
  if (eventKey === "") {
    return "No event is set. Set one in Settings to list its teams.";
  }
  if (status === "none" || status === "loading") {
    return "Loading the event's teams.";
  }
  if (status === "failed") {
    return "Could not load the event's teams. Open a team by number below.";
  }
  return "The event has no teams listed yet. Open a team by number below.";
}
