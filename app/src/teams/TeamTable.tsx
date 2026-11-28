import { PickedMark } from "../picks/PickedMark";
import { formatStat } from "../team/format";
import { TeamLink } from "../ui/TeamLink";
import { maxCompare } from "./compare";
import type { Heat, HeatKey, HeatMap } from "./heat";
import { CompareCheck, Missing, Sparkline } from "./parts";
import { signed, type TeamRow, worksText } from "./rows";
import { type Sort, type SortKey, sortKeys } from "./sort";

interface Column {
  key: SortKey;
  label: string;
  title: string;
}

const columns: Column[] = [
  { key: "epa", label: "EPA", title: "Statbotics expected points added" },
  { key: "rank", label: "Rank", title: "Official qualification rank" },
  {
    key: "total",
    label: "Score",
    title:
      "Scouted score: the typical match total, leaving out breakdown matches and matches far from the team's usual",
  },
  {
    key: "floor",
    label: "Floor",
    title:
      "A bad day: the 25th percentile of the matches the score counts. Needs 4 matches",
  },
  {
    key: "auto",
    label: "Auto",
    title: "Typical auto, same matches as the score",
  },
  {
    key: "teleop",
    label: "Teleop",
    title: "Typical teleop, same matches as the score",
  },
  {
    key: "sd",
    label: "SD",
    title: "Spread of the match total, lower is steadier. Needs 3 matches",
  },
  {
    key: "reliable",
    label: "Works",
    title: "Matches without a breakdown (died, disconnected or no show)",
  },
  {
    key: "form",
    label: "Form",
    title:
      "Last 3 match totals against the ones before. Needs 5 matches. It predicted worst in a backtest on 2026 event data, so use it to spot a change, not to rank",
  },
  { key: "climb", label: "Climb", title: "Highest endgame climb seen" },
  { key: "matches", label: "n", title: "Matches scouted" },
];

function Chevron({ up }: { up: boolean }) {
  return (
    <svg
      className="teams-chevron"
      viewBox="0 0 24 24"
      width="16"
      height="16"
      aria-hidden="true"
      focusable="false"
      style={{ transform: up ? "rotate(180deg)" : undefined }}
    >
      <path d="M6 9l6 6 6-6" />
    </svg>
  );
}

function SortHead({
  column,
  sort,
  onSort,
  left,
}: {
  column: Column;
  sort: Sort;
  onSort: (key: SortKey) => void;
  left?: boolean;
}) {
  const active = sort.key === column.key;
  const descending = sortKeys[column.key].descending !== sort.reversed;
  return (
    <th
      scope="col"
      className={left ? "teams-left" : undefined}
      aria-sort={active ? (descending ? "descending" : "ascending") : undefined}
    >
      <button
        type="button"
        className="teams-sortbtn"
        title={column.title}
        data-active={active || undefined}
        onClick={() => onSort(column.key)}
      >
        {column.label}
        {active && <Chevron up={!descending} />}
      </button>
    </th>
  );
}

const num = (n: number | null) => (n === null ? null : formatStat(n));

function Cell({
  text,
  heat,
}: {
  text: string | null;
  heat?: Heat | undefined;
}) {
  return <td data-heat={heat ? heat : undefined}>{text ?? <Missing />}</td>;
}

export interface TableProps {
  rows: TeamRow[];
  places: Map<number, number>;
  heat: HeatMap;
  sort: Sort;
  onSort: (key: SortKey) => void;
  taken: Record<number, string>;
  chosen: number[];
  onToggle: (team: number) => void;
}

export function TeamTable({
  rows,
  places,
  heat,
  sort,
  onSort,
  taken,
  chosen,
  onToggle,
}: TableProps) {
  const full = chosen.length >= maxCompare;
  return (
    <div className="teams-scroll">
      <table className="teams-table">
        <caption className="sr-only">
          Event teams. Press a column heading to sort.
        </caption>
        <thead>
          <tr>
            <SortHead
              column={{
                key: "number",
                label: "Team",
                title: "Team number",
              }}
              sort={sort}
              onSort={onSort}
              left
            />
            {columns.map((c) => (
              <SortHead key={c.key} column={c} sort={sort} onSort={onSort} />
            ))}
            <th scope="col">Trend</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const picked = taken[r.team] !== undefined;
            const level = (key: HeatKey): Heat | undefined =>
              picked ? undefined : heat[key].get(r.team);
            return (
              <tr key={r.team} data-picked={picked || undefined}>
                <th scope="row" className="teams-team">
                  <div className="teams-cell">
                    <CompareCheck
                      team={r.team}
                      checked={chosen.includes(r.team)}
                      disabled={full}
                      onToggle={onToggle}
                    />
                    <span className="teams-place" title="Place in EPA order">
                      {places.get(r.team)}
                    </span>
                    <span className="teams-id">
                      <span className="teams-name">
                        <TeamLink team={r.team} />
                        {r.nickname !== "" && (
                          <span className="teams-nick">{r.nickname}</span>
                        )}
                      </span>
                      <PickedMark team={r.team} />
                      {!r.listed && (
                        <span className="secondary">Not on the team list</span>
                      )}
                    </span>
                  </div>
                </th>
                <Cell text={num(r.epa)} heat={level("epa")} />
                <Cell text={r.rank === null ? null : String(r.rank)} />
                <Cell text={num(r.total)} heat={level("total")} />
                <Cell text={num(r.floor)} heat={level("floor")} />
                <Cell text={num(r.auto)} heat={level("auto")} />
                <Cell text={num(r.teleop)} heat={level("teleop")} />
                <Cell text={num(r.sd)} heat={level("sd")} />
                <Cell text={worksText(r)} />
                <Cell
                  text={r.form === null ? null : signed(r.form)}
                  heat={level("form")}
                />
                <Cell text={r.climb > 0 ? `L${r.climb}` : null} />
                <Cell text={r.matches > 0 ? String(r.matches) : null} />
                <td>
                  <Sparkline series={r.series} />
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
