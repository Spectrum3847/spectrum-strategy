import { useState } from "react";
import { Link } from "react-router";
import { compareHref } from "../teams/compare";
import { CompareCheck } from "../teams/parts";
import { TeamLink } from "../ui/TeamLink";
import { FactLines } from "./Columns";
import { noFacts, type TeamFacts, tiedWithAbove } from "./facts";
import { layoutOf, type PickList } from "./pickList";

export function ReadOnlyList({
  list,
  facts,
  taken,
}: {
  list: PickList;
  facts: Map<number, TeamFacts>;
  taken: Map<number, string>;
}) {
  const layout = layoutOf(list);
  const tiedWith = tiedWithAbove(
    layout.tiers.flatMap((t) => t.teams),
    facts,
  );
  const [chosen, setChosen] = useState<number[]>([]);
  const toggle = (team: number) =>
    setChosen((current) =>
      current.includes(team)
        ? current.filter((t) => t !== team)
        : current.length < 3
          ? [...current, team]
          : current,
    );
  let rank = 0;
  return (
    <div className="pick-list">
      <div className="pick-list-head">
        <h2>{list.name}</h2>
      </div>
      <div className="actions">
        <p className="secondary">
          Tick 2 or 3 teams to compare. {chosen.join(", ")}
        </p>
        {chosen.length >= 2 ? (
          <Link className="btn" to={compareHref(chosen)}>
            Compare
          </Link>
        ) : (
          <button className="btn" disabled type="button">
            Compare
          </button>
        )}
      </div>
      <div className="pick-columns">
        <div className="pick-tiers">
          {layout.tiers.map((tier, i) => (
            // biome-ignore lint/suspicious/noArrayIndexKey: tiers have no id
            <section className="pick-tier" key={i} aria-labelledby={`ro-${i}`}>
              <header className="pick-tier-head">
                <h3 id={`ro-${i}`}>
                  {tier.name}{" "}
                  <span className="secondary">({tier.teams.length})</span>
                </h3>
              </header>
              <ol className="plain pick-rows">
                {tier.teams.length === 0 && (
                  <li className="secondary pick-empty">No teams.</li>
                )}
                {tier.teams.map((team) => {
                  rank += 1;
                  return (
                    <li className="pick-row" key={team} data-row-team={team}>
                      <div className="pick-main">
                        <CompareCheck
                          team={team}
                          checked={chosen.includes(team)}
                          disabled={chosen.length >= 3}
                          onToggle={toggle}
                        />
                        <span className="pick-rank">{rank}</span>
                        <TeamLink team={team} />
                      </div>
                      <div className="pick-facts">
                        <FactLines
                          facts={facts.get(team) ?? noFacts}
                          taken={taken.get(team)}
                          tiedWith={tiedWith.get(team)}
                        />
                      </div>
                    </li>
                  );
                })}
              </ol>
            </section>
          ))}
        </div>
      </div>
      <section className="pick-section" aria-labelledby="ro-dnp-h">
        <h2 id="ro-dnp-h">
          Do not pick <span className="secondary">({layout.dnp.length})</span>
        </h2>
        <ul className="plain pick-rows">
          {layout.dnp.length === 0 && (
            <li className="secondary pick-empty">No teams on this list.</li>
          )}
          {layout.dnp.map((d) => (
            <li className="pick-row" key={d.team} data-row-team={d.team}>
              <div className="pick-main">
                <CompareCheck
                  team={d.team}
                  checked={chosen.includes(d.team)}
                  disabled={chosen.length >= 3}
                  onToggle={toggle}
                />
                <TeamLink team={d.team} />
                <p className="pick-reason">{d.reason}</p>
              </div>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
