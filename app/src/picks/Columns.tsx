import { type KeyboardEvent, useState } from "react";
import { CompareCheck } from "../teams/parts";
import { TeamLink } from "../ui/TeamLink";
import type { RowDrag } from "./drag";
import type { TeamFacts } from "./facts";
import { noFacts, statLine } from "./facts";
import { describe as describeIncidents } from "./incidents";
import {
  DownIcon,
  GripIcon,
  InlineForm,
  MoreIcon,
  reasonError,
  teamError,
  UpIcon,
} from "./parts";
import {
  addTier,
  type Layout,
  placeTeam,
  removeTeam,
  removeTier,
  renameTier,
} from "./pickList";

export interface Editing {
  layout: Layout;
  chosen: number[];
  toggleCompare(team: number): void;
  facts: Map<number, TeamFacts>;
  tiedWith: Map<number, number>;
  taken: Map<number, string>;
  known: number[];
  drag: RowDrag;
  change(next: Layout): void;
  move(team: number, delta: -1 | 1): void;
  onHandleKey(e: KeyboardEvent, team: number): void;
  markDnp(team: number, reason: string): void;
  notify(text: string): void;
}

export function FactLines({
  facts,
  taken,
  tiedWith,
}: {
  facts: TeamFacts;
  taken?: string | undefined;
  tiedWith?: number | undefined;
}) {
  return (
    <>
      {taken && <p className="pick-taken">{taken}</p>}
      <p className="secondary">{statLine(facts)}</p>
      {tiedWith !== undefined && (
        <p
          className="pick-tie"
          title="The scores differ by less than their ± together, so rank them on climb, reliability or video."
        >
          {`≈ tied with ${tiedWith}`}
        </p>
      )}
      {facts.robotType !== "" && <p className="secondary">{facts.robotType}</p>}
      {facts.incidents && (
        <p className="pick-incidents">{describeIncidents(facts.incidents)}</p>
      )}
    </>
  );
}

function TeamRow({
  team,
  rank,
  tier,
  first,
  last,
  e,
}: {
  team: number;
  rank: number;
  tier: number;
  first: boolean;
  last: boolean;
  e: Editing;
}) {
  const [open, setOpen] = useState(false);
  const [dnp, setDnp] = useState(false);
  const facts = e.facts.get(team) ?? noFacts;
  const taken = e.taken.get(team);
  const { tiers } = e.layout;
  return (
    <li
      className="pick-row"
      data-row-team={team}
      data-taken={taken ? "true" : undefined}
      data-dragging={e.drag.dragging === team ? "true" : undefined}
    >
      <div className="pick-main">
        <button
          type="button"
          className="pick-handle"
          data-handle={team}
          aria-label={`Reorder ${team}`}
          aria-describedby="pick-keys"
          onKeyDown={(k) => e.onHandleKey(k, team)}
          {...e.drag.handlers(team)}
        >
          <GripIcon />
        </button>
        <CompareCheck
          team={team}
          checked={e.chosen.includes(team)}
          disabled={e.chosen.length >= 3}
          onToggle={e.toggleCompare}
        />
        <span className="pick-rank">{rank}</span>
        <TeamLink team={team} />
        <span className="pick-actions">
          <button
            type="button"
            className="icon-btn"
            aria-label={`Move ${team} up`}
            disabled={first}
            onClick={() => e.move(team, -1)}
          >
            <UpIcon />
          </button>
          <button
            type="button"
            className="icon-btn"
            aria-label={`Move ${team} down`}
            disabled={last}
            onClick={() => e.move(team, 1)}
          >
            <DownIcon />
          </button>
          <button
            type="button"
            className="icon-btn"
            aria-label={`More for ${team}`}
            aria-expanded={open}
            onClick={() => {
              setOpen(!open);
              setDnp(false);
            }}
          >
            <MoreIcon />
          </button>
        </span>
      </div>
      <div className="pick-facts">
        <FactLines
          facts={facts}
          taken={taken}
          tiedWith={e.tiedWith.get(team)}
        />
      </div>
      {open && (
        <div className="pick-panel">
          <label className="pick-field">
            <span className="label">Move {team} to</span>
            <select
              className="input"
              value=""
              onChange={(ev) => {
                if (ev.target.value === "") return;
                e.change(placeTeam(e.layout, team, Number(ev.target.value)));
                setOpen(false);
              }}
            >
              <option value="">Choose a tier</option>
              {tiers.map(
                (t, i) =>
                  i !== tier && (
                    // biome-ignore lint/suspicious/noArrayIndexKey: tiers have no id
                    <option key={i} value={i}>
                      {t.name}
                    </option>
                  ),
              )}
            </select>
          </label>
          {dnp ? (
            <InlineForm
              fields={[{ label: `Why not ${team}`, max: 200 }]}
              submit="Do not pick"
              validate={([reason]) => reasonError(reason ?? "")}
              onSubmit={([reason]) => e.markDnp(team, reason ?? "")}
            />
          ) : (
            <div className="actions">
              <button
                type="button"
                className="btn"
                onClick={() => setDnp(true)}
              >
                Do not pick
              </button>
              <button
                type="button"
                className="btn"
                onClick={() => e.change(removeTeam(e.layout, team))}
              >
                Remove
              </button>
            </div>
          )}
        </div>
      )}
    </li>
  );
}

function Tier({
  index,
  startRank,
  total,
  e,
}: {
  index: number;
  startRank: number;
  total: number;
  e: Editing;
}) {
  const [open, setOpen] = useState(false);
  const tier = e.layout.tiers[index];
  if (!tier) return null;
  const over = e.drag.over;
  const here = over?.kind === "tier" && over.tier === index ? over.index : null;
  const heading = `tier-h-${index}`;
  const line = <li key="drop" className="pick-drop" aria-hidden="true" />;
  const rows = tier.teams.filter((t) => t !== e.drag.dragging);
  return (
    <section
      className="pick-tier"
      data-drop={`tier-${index}`}
      data-over={here !== null ? "true" : undefined}
      aria-labelledby={heading}
    >
      <header className="pick-tier-head">
        <h3 id={heading}>
          {tier.name} <span className="secondary">({tier.teams.length})</span>
        </h3>
        <button
          type="button"
          className="icon-btn"
          aria-label={`Options for ${tier.name}`}
          aria-expanded={open}
          onClick={() => setOpen(!open)}
        >
          <MoreIcon />
        </button>
      </header>
      {open && (
        <div className="pick-panel">
          <InlineForm
            fields={[{ label: "Add a team", digits: true, max: 5 }]}
            submit="Add"
            validate={([text]) => teamError(text ?? "", e.known)}
            onSubmit={([text]) =>
              e.change(placeTeam(e.layout, Number(text), index))
            }
          />
          <InlineForm
            fields={[{ label: "Tier name", initial: tier.name, max: 128 }]}
            submit="Rename"
            validate={([name]) =>
              name === "" ? "Give the tier a name." : null
            }
            onSubmit={([name]) =>
              e.change(renameTier(e.layout, index, name ?? ""))
            }
          />
          {tier.teams.length === 0 && e.layout.tiers.length > 1 && (
            <button
              type="button"
              className="btn"
              onClick={() => e.change(removeTier(e.layout, index))}
            >
              Remove {tier.name}
            </button>
          )}
        </div>
      )}
      <ol className="plain pick-rows">
        {tier.teams.length === 0 && (
          <li className="secondary pick-empty">
            No teams. Add one, or drag a team here.
          </li>
        )}
        {tier.teams.flatMap((team, i) => {
          const row = (
            <TeamRow
              key={team}
              team={team}
              rank={startRank + i}
              tier={index}
              first={startRank + i === 1}
              last={startRank + i === total}
              e={e}
            />
          );
          const before = rows.indexOf(team);
          return before === here ? [line, row] : [row];
        })}
        {here !== null && here >= rows.length && line}
      </ol>
    </section>
  );
}

export function Columns({ e, total }: { e: Editing; total: number }) {
  const [adding, setAdding] = useState(false);
  let start = 1;
  return (
    <div className="pick-columns">
      <div className="pick-tiers">
        {e.layout.tiers.map((tier, i) => {
          const at = start;
          start += tier.teams.length;
          return (
            <Tier
              // biome-ignore lint/suspicious/noArrayIndexKey: tiers have no id
              key={i}
              index={i}
              startRank={at}
              total={total}
              e={e}
            />
          );
        })}
      </div>
      {adding ? (
        <InlineForm
          fields={[{ label: "New tier name", max: 128 }]}
          submit="Add tier"
          validate={([name]) => (name === "" ? "Give the tier a name." : null)}
          onSubmit={([name]) => {
            e.change(addTier(e.layout, name ?? ""));
            setAdding(false);
          }}
        />
      ) : (
        <button type="button" className="btn" onClick={() => setAdding(true)}>
          Add tier
        </button>
      )}
    </div>
  );
}
