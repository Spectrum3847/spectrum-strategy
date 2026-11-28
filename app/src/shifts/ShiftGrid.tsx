import type { ScoutShifts } from "../scout/credit";
import {
  type Cell,
  type CellColor,
  colorAt,
  labelAt,
  noteAt,
  stationAt,
} from "./schedule";

export interface ShiftGridProps {
  shifts: ScoutShifts;
  mineUid: string | null;
  anchor?: Cell | null | undefined;
  onCell?: ((cell: Cell) => void) | undefined;
}

const colorWord: Record<CellColor, string> = {
  green: "on duty",
  white: "off",
  grey: "grey",
  red: "unavailable",
};

export function ShiftGrid({ shifts, mineUid, anchor, onCell }: ShiftGridProps) {
  const matches = Array.from({ length: shifts.matchCount }, (_, i) => i + 1);
  return (
    <div className="shift-scroll">
      <table className="shift-grid">
        <caption className="sr-only">Scouting shifts by match</caption>
        <thead>
          <tr>
            <th scope="col">Match</th>
            {shifts.roster.map((r, col) => (
              <th
                // biome-ignore lint/suspicious/noArrayIndexKey: columns are positional
                key={col}
                scope="col"
                title={r.name}
                data-mine={
                  mineUid !== null && r.uid === mineUid ? "" : undefined
                }
              >
                <span className="clip">
                  {r.name === "" ? "(no name)" : r.name}
                </span>
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {matches.map((match) => (
            <tr key={match}>
              <th scope="row">{match}</th>
              {shifts.roster.map((r, col) => {
                const color = colorAt(shifts, col, match);
                const label = labelAt(shifts, col, match);
                const picked = anchor?.col === col && anchor.match === match;
                const summary = [
                  r.name,
                  `match ${match}`,
                  colorWord[color],
                  stationAt(shifts, col, match),
                  noteAt(shifts, col, match),
                ]
                  .filter(Boolean)
                  .join(", ");
                return (
                  <td
                    // biome-ignore lint/suspicious/noArrayIndexKey: columns are positional
                    key={col}
                    data-color={color}
                    data-anchor={picked ? "" : undefined}
                  >
                    {onCell ? (
                      <button
                        type="button"
                        className="cell"
                        aria-label={summary}
                        onClick={() => onCell({ col, match })}
                      >
                        <span className="clip" title={label}>
                          {label}
                        </span>
                      </button>
                    ) : (
                      <>
                        {color !== "white" && (
                          <span className="sr-only">{`${colorWord[color]}, `}</span>
                        )}
                        <span className="clip" title={label}>
                          {label}
                        </span>
                      </>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
