import { PickedMark } from "../picks/PickedMark";
import { formatStat } from "../team/format";
import { TeamLink } from "../ui/TeamLink";
import { maxCompare } from "./compare";
import { CompareCheck, Sparkline } from "./parts";
import { signed, type TeamRow, worksText } from "./rows";

const one = (n: number) => formatStat(n);

function figures(r: TeamRow): [string, string] {
  const first = [
    r.epa !== null ? `EPA ${one(r.epa)}` : "",
    r.rank !== null ? `Rank ${r.rank} (${r.record})` : "",
    r.total !== null ? `Score ${one(r.total)}` : "Not scouted",
    r.matches > 0 ? `n ${r.matches}` : "",
  ];
  const second = [
    r.auto !== null ? `Auto ${one(r.auto)}` : "",
    r.teleop !== null ? `Teleop ${one(r.teleop)}` : "",
    r.floor !== null ? `Floor ${one(r.floor)}` : "",
    r.sd !== null ? `SD ${one(r.sd)}` : "",
    r.reliability ? `Works ${worksText(r)}` : "",
    r.form !== null ? `Form ${signed(r.form)}` : "",
    r.climb > 0 ? `Climb L${r.climb}` : "",
  ];
  const join = (parts: string[]) => parts.filter((p) => p !== "").join(" · ");
  return [join(first), join(second)];
}

export function TeamList({
  rows,
  places,
  taken,
  chosen,
  onToggle,
}: {
  rows: TeamRow[];
  places: Map<number, number>;
  taken: Record<number, string>;
  chosen: number[];
  onToggle: (team: number) => void;
}) {
  const full = chosen.length >= maxCompare;
  return (
    <ol className="teams-list" aria-label="Event teams">
      {rows.map((r) => {
        const [first, second] = figures(r);
        return (
          <li
            key={r.team}
            className="teams-item"
            data-picked={taken[r.team] !== undefined || undefined}
          >
            <CompareCheck
              team={r.team}
              checked={chosen.includes(r.team)}
              disabled={full}
              onToggle={onToggle}
            />
            <div className="teams-main">
              <p className="teams-name">
                <span className="teams-place" title="Place in EPA order">
                  {places.get(r.team)}
                </span>
                <TeamLink team={r.team} />
                {r.nickname !== "" && (
                  <span className="teams-nick">{r.nickname}</span>
                )}
              </p>
              <PickedMark team={r.team} />
              {!r.listed && <p className="secondary">Not on the team list</p>}
              <p className="secondary">{first}</p>
              {second !== "" && <p className="secondary">{second}</p>}
            </div>
            <div className="teams-trend">
              <Sparkline series={r.series} />
            </div>
          </li>
        );
      })}
    </ol>
  );
}
