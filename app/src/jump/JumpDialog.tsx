import {
  type KeyboardEvent,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
} from "react";
import { useNavigate } from "react-router";
import { canOpenMatchPage, canOpenTeamPage } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { useTbaEvent } from "../data/useTbaEvent";
import { resolveJump } from "./parse";

const focusable = "input, button:not([disabled])";

export function JumpDialog({ onClose }: { onClose(): void }) {
  const roles = useRoles();
  const { eventKey, teams, matches } = useTbaEvent();
  const navigate = useNavigate();
  const [text, setText] = useState("");
  const [error, setError] = useState<string | null>(null);
  const dialog = useRef<HTMLDivElement>(null);
  const input = useRef<HTMLInputElement>(null);
  const titleId = useId();
  const errorId = useId();

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    input.current?.focus();
    return () => opener?.focus();
  }, []);

  const ctx = useMemo(() => {
    const granted = roles.status === "ready" ? roles.roles : [];
    return {
      eventKey,
      knownTeams: new Set(teams.map((t) => t.number)),
      matchKeys: matches.map((m) => m.key),
      canTeam: canOpenTeamPage(granted),
      canMatch: canOpenMatchPage(granted),
    };
  }, [roles, eventKey, teams, matches]);

  const result = text.trim() === "" ? null : resolveJump(text, ctx);
  const match = result?.ok && result.kind === "match" ? result : null;

  function open(path: string) {
    onClose();
    navigate(path);
  }

  function submit() {
    const r = resolveJump(text, ctx);
    if (r.ok) open(r.path);
    else setError(r.message);
  }

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") {
      e.stopPropagation();
      onClose();
      return;
    }
    if (e.key !== "Tab") return;
    const items = [
      ...(dialog.current?.querySelectorAll<HTMLElement>(focusable) ?? []),
    ];
    const first = items[0];
    const last = items[items.length - 1];
    if (!first || !last) return;
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    <div className="sheet-scrim jump-scrim">
      <button
        type="button"
        className="sheet-backdrop"
        tabIndex={-1}
        aria-hidden="true"
        onClick={onClose}
      />
      <div
        ref={dialog}
        className="sheet jump-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onKeyDown={onKeyDown}
      >
        <form
          className="jump-form"
          onSubmit={(e) => {
            e.preventDefault();
            submit();
          }}
        >
          <h2 id={titleId}>Go to team or match</h2>
          <label className="field-name" htmlFor={`${titleId}-q`}>
            Team number or match
          </label>
          <input
            id={`${titleId}-q`}
            ref={input}
            className="input"
            type="text"
            value={text}
            placeholder="3847 or q45"
            autoComplete="off"
            autoCapitalize="none"
            spellCheck={false}
            enterKeyHint="go"
            aria-invalid={error !== null}
            aria-describedby={error ? errorId : undefined}
            onChange={(e) => {
              setText(e.target.value.replace(/[^a-zA-Z0-9 ]/g, ""));
              setError(null);
            }}
          />
          {error && (
            <p id={errorId} className="notice" role="alert">
              {error}
            </p>
          )}
          {match && (
            <button
              type="button"
              className="btn jump-result"
              onClick={() => open(match.path)}
            >
              <span>{match.label}</span>
              <span className="secondary">Match</span>
            </button>
          )}
          <div className="jump-actions">
            <button type="button" className="btn" onClick={onClose}>
              Cancel
            </button>
            <button type="submit" className="btn primary">
              Go
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
