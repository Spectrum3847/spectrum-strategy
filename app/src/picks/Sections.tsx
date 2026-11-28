import { useMemo, useState } from "react";
import { CompareCheck } from "../teams/parts";
import { TeamLink } from "../ui/TeamLink";
import { type Editing, FactLines } from "./Columns";
import { noFacts, statLine } from "./facts";
import { describe, type Incidents, suggestions, weight } from "./incidents";
import { GripIcon, InlineForm, reasonError, teamError } from "./parts";
import { markDnp, placeTeam, removeTeam, setReason } from "./pickList";

function TierSelect({
  label,
  names,
  skip,
  onPick,
}: {
  label: string;
  names: string[];
  skip?: number;
  onPick(tier: number): void;
}) {
  return (
    <div className="pick-field">
      <select
        className="input"
        aria-label={label}
        value=""
        onChange={(ev) => {
          if (ev.target.value !== "") onPick(Number(ev.target.value));
        }}
      >
        <option value="">{label}</option>
        {names.map(
          (name, i) =>
            i !== skip && (
              // biome-ignore lint/suspicious/noArrayIndexKey: tiers have no id
              <option key={i} value={i}>
                {name}
              </option>
            ),
        )}
      </select>
    </div>
  );
}

function DnpRow({
  team,
  reason,
  e,
}: {
  team: number;
  reason: string;
  e: Editing;
}) {
  const [editing, setEditing] = useState(false);
  const names = e.layout.tiers.map((t) => t.name);
  return (
    <li className="pick-row" data-row-team={team}>
      <div className="pick-main">
        <CompareCheck
          team={team}
          checked={e.chosen.includes(team)}
          disabled={e.chosen.length >= 3}
          onToggle={e.toggleCompare}
        />
        <TeamLink team={team} />
        <p className="pick-reason">{reason}</p>
      </div>
      <div className="pick-facts">
        <p className="secondary">{statLine(e.facts.get(team) ?? noFacts)}</p>
      </div>
      <div className="pick-panel">
        {editing ? (
          <InlineForm
            fields={[
              { label: `Reason for ${team}`, initial: reason, max: 200 },
            ]}
            submit="Save"
            validate={([text]) => reasonError(text ?? "")}
            onSubmit={([text]) => {
              e.change(setReason(e.layout, team, text ?? ""));
              setEditing(false);
            }}
          />
        ) : (
          <div className="actions">
            <button
              type="button"
              className="btn"
              onClick={() => setEditing(true)}
            >
              Edit reason for {team}
            </button>
            <button
              type="button"
              className="btn"
              onClick={() => e.change(removeTeam(e.layout, team))}
            >
              Remove {team}
            </button>
          </div>
        )}
        <TierSelect
          label={`Move ${team} to a tier`}
          names={names}
          onPick={(tier) => e.change(placeTeam(e.layout, team, tier))}
        />
      </div>
    </li>
  );
}

export function DnpSection({ e, us }: { e: Editing; us: number | null }) {
  const { dnp } = e.layout;
  const byTeam = useMemo(() => {
    const out = new Map<number, Incidents>();
    for (const [team, facts] of e.facts) {
      if (facts.incidents) out.set(team, facts.incidents);
    }
    return out;
  }, [e.facts]);
  const listed = new Set(dnp.map((d) => d.team));
  const suggested = suggestions(byTeam, listed, us);
  const watch = [...byTeam]
    .filter(([team, i]) => weight(i) === 1 && !listed.has(team) && team !== us)
    .sort(([a], [b]) => a - b);
  const add = (list: { team: number; reason: string }[]) => {
    let next = e.layout;
    for (const s of list) next = markDnp(next, s.team, s.reason);
    e.change(next);
    return list.filter((s) => next.dnp.some((d) => d.team === s.team));
  };
  const addLikely = () => {
    const added = add(suggested);
    if (added.length > 0) {
      e.notify(
        `Added ${added.length} to do not pick: ${added.map((s) => s.team).join(", ")}.`,
      );
    }
  };
  return (
    <section className="pick-section" aria-labelledby="dnp-h">
      <h2 id="dnp-h">
        Do not pick <span className="secondary">({dnp.length})</span>
      </h2>
      <p className="secondary">
        Mostly robots that got a card or died. Every team needs a reason.
      </p>
      <InlineForm
        fields={[
          { label: "Team number", digits: true, max: 5 },
          { label: "Reason", max: 200 },
        ]}
        submit="Add to do not pick"
        validate={([team, reason]) =>
          teamError(team ?? "", e.known) ?? reasonError(reason ?? "")
        }
        onSubmit={([team, reason]) => e.markDnp(Number(team), reason ?? "")}
      />
      <ul className="plain pick-rows">
        {dnp.length === 0 && (
          <li className="secondary pick-empty">No teams on this list.</li>
        )}
        {dnp.map((d) => (
          <DnpRow key={d.team} team={d.team} reason={d.reason} e={e} />
        ))}
      </ul>
      {watch.length > 0 && (
        <div className="pick-suggest">
          <h3>Watch ({watch.length})</h3>
          <p className="secondary">
            One card or death. Check the video before deciding.
          </p>
          <ul className="plain pick-rows">
            {watch.map(([team, incident]) => (
              <li className="pick-row" key={team}>
                <div className="pick-main">
                  <TeamLink team={team} />
                  <p className="pick-reason">{describe(incident)}</p>
                  <button
                    type="button"
                    className="btn"
                    onClick={() => add([{ team, reason: describe(incident) }])}
                  >
                    Add {team}
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
      {suggested.length === 0 && watch.length > 0 && (
        <p className="secondary">
          No likely teams: none has a red card, or 2 cards, deaths or
          disconnects.
        </p>
      )}
      {suggested.length > 0 && (
        <div className="pick-suggest">
          <div className="pick-main">
            <h3>Likely ({suggested.length})</h3>
            <button type="button" className="btn" onClick={addLikely}>
              Add likely ({suggested.length})
            </button>
          </div>
          <p className="secondary">
            A red card, or any 2 cards, deaths or disconnects. Check the video
            before adding.
          </p>
          <ul className="plain pick-rows">
            {suggested.map((s) => {
              const tier = e.layout.tiers.find((t) => t.teams.includes(s.team));
              return (
                <li className="pick-row" key={s.team}>
                  <div className="pick-main">
                    <TeamLink team={s.team} />
                    <p className="pick-reason">{s.reason}</p>
                    <button
                      type="button"
                      className="btn"
                      aria-label={`Add ${s.team} to do not pick`}
                      onClick={() => add([s])}
                    >
                      Add
                    </button>
                  </div>
                  {tier && (
                    <p className="secondary pick-facts">Now on {tier.name}</p>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </section>
  );
}

export function PoolSection({
  teams,
  nicknames,
  e,
}: {
  teams: number[];
  nicknames: Map<number, string>;
  e: Editing;
}) {
  const [find, setFind] = useState("");
  const names = e.layout.tiers.map((t) => t.name);
  const needle = find.trim().toLowerCase();
  const shown = needle
    ? teams.filter(
        (t) =>
          String(t).startsWith(needle) ||
          (nicknames.get(t) ?? "").toLowerCase().includes(needle),
      )
    : teams;
  const over = e.drag.over?.kind === "pool";
  return (
    <section
      className="pick-section"
      data-drop="pool"
      data-over={over ? "true" : undefined}
      aria-labelledby="pool-h"
    >
      <h2 id="pool-h">
        Not ranked <span className="secondary">({teams.length})</span>
      </h2>
      <p className="secondary">
        Event teams on no tier. Drag a ranked team here to take it off the list.
      </p>
      {teams.length === 0 ? (
        <p className="secondary pick-empty">
          {e.known.length === 0
            ? "No teams are loaded for this event yet. Pick your event in Settings."
            : "Every team is on a tier or on do not pick."}
        </p>
      ) : (
        <>
          <label className="pick-field">
            <span className="label">Find a team</span>
            <input
              className="input"
              value={find}
              onChange={(ev) => setFind(ev.target.value)}
            />
          </label>
          <ul className="plain pick-rows">
            {shown.length === 0 && (
              <li className="secondary pick-empty">No team matches.</li>
            )}
            {shown.map((team) => (
              <li className="pick-row" key={team} data-row-team={team}>
                <div className="pick-main">
                  <span
                    className="pick-handle"
                    aria-hidden="true"
                    {...e.drag.handlers(team)}
                  >
                    <GripIcon />
                  </span>
                  <CompareCheck
                    team={team}
                    checked={e.chosen.includes(team)}
                    disabled={e.chosen.length >= 3}
                    onToggle={e.toggleCompare}
                  />
                  <TeamLink team={team} />
                  <span className="pick-nick">{nicknames.get(team) ?? ""}</span>
                </div>
                <div className="pick-facts">
                  <FactLines facts={e.facts.get(team) ?? noFacts} />
                </div>
                <TierSelect
                  label={`Add ${team} to a tier`}
                  names={names}
                  onPick={(tier) => e.change(placeTeam(e.layout, team, tier))}
                />
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}
