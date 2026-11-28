import { windowNote, windowOptions } from "./window";

export function MatchWindow({
  last,
  total,
  onChange,
}: {
  last: number | null;
  total: number;
  onChange(next: number | null): void;
}) {
  return (
    <div className="team-window">
      <fieldset className="chips">
        <legend className="label">Matches used</legend>
        {windowOptions.map((o) => (
          <button
            key={o.label}
            type="button"
            className="chip"
            aria-pressed={last === o.last}
            onClick={() => onChange(o.last)}
          >
            {o.label}
          </button>
        ))}
      </fieldset>
      <p className="secondary" role="status">
        {windowNote(last, total)}
      </p>
    </div>
  );
}
