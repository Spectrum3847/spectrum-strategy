import { useState } from "react";
import { TeamLink } from "../ui/TeamLink";
import { allianceFit } from "./allianceFit";
import {
  allianceSize,
  backups,
  canInvite,
  type DraftAction,
  type DraftBoard,
  isComplete,
  picksUntil,
  type Rounds,
  roundOf,
  roundOptions,
} from "./draft";
import { record, setActions, setRounds, undo } from "./draftStore";
import { noFacts, statLine, type TeamFacts } from "./facts";
import { InlineForm, teamError } from "./parts";
import type { Layout } from "./pickList";

const listed = 24;

interface Candidate {
  team: number;
  label: string;
  dnpReason: string | null;
}

function candidatesFor(
  board: DraftBoard,
  layout: Layout | null,
  ranking: number[],
): Candidate[] {
  const out: Candidate[] = [];
  const seen = new Set<number>();
  const dnp = new Map(layout?.dnp.map((d) => [d.team, d.reason]) ?? []);
  const add = (team: number, label: string) => {
    if (out.length >= listed || !canInvite(board, team) || seen.has(team))
      return;
    seen.add(team);
    out.push({ team, label, dnpReason: dnp.get(team) ?? null });
  };
  for (const tier of layout?.tiers ?? []) {
    for (const team of tier.teams) add(team, tier.name);
  }
  for (const team of ranking) add(team, "Not on the list");
  return out;
}

export function DraftView({
  eventKey,
  canEdit,
  board,
  actions,
  rounds,
  roundsFrom,
  facts,
  layout,
  ranking,
  official,
  us,
}: {
  eventKey: string;
  canEdit: boolean;
  board: DraftBoard;
  actions: DraftAction[];
  rounds: Rounds;
  roundsFrom: string;
  facts: Map<number, TeamFacts>;
  layout: Layout | null;
  ranking: number[];
  official: number[];
  us: number | null;
}) {
  const [resetFrom, setResetFrom] = useState<DraftAction[] | null>(null);
  const picking = board.picking;
  const until = us === null ? null : picksUntil(board, us);
  const free = candidatesFor(board, layout, ranking);
  const spare = backups(board, official);
  const last = actions[actions.length - 1];
  const ours = board.alliances.find((a) => us !== null && a.teams.includes(us));

  const act = (team: number, declined: boolean) => {
    setResetFrom(null);
    record(eventKey, team, declined);
  };

  if (board.alliances.length === 0) {
    return (
      <p className="secondary">
        No teams are loaded for this event yet. Pick your event in Settings to
        run the draft.
      </p>
    );
  }

  return (
    <div className="draft">
      <div className="draft-clock">
        <p className="secondary">
          {picking === null
            ? "Draft complete"
            : `Round ${roundOf(board) + 1} of ${board.rounds}`}
        </p>
        <h2>
          {picking === null
            ? "Every alliance is full."
            : `Alliance ${picking + 1} is on the clock`}
        </h2>
        {until !== null && (
          <p className="draft-us">
            {until === 0
              ? "We are on the clock."
              : `We pick in ${until} ${until === 1 ? "pick" : "picks"}.`}
          </p>
        )}
      </div>

      <div className="actions">
        <fieldset className="chips" aria-label="Draft rounds">
          {roundOptions.map((n) => (
            <button
              key={n}
              type="button"
              className="chip"
              disabled={!canEdit}
              aria-pressed={rounds === n}
              onClick={() => setRounds(eventKey, n)}
            >
              {n} rounds
            </button>
          ))}
        </fieldset>
        <button
          type="button"
          className="btn"
          disabled={!canEdit || actions.length === 0}
          onClick={() => undo(eventKey)}
        >
          {last
            ? `Undo ${last.declined ? "decline" : "pick"} of ${last.team}`
            : "Undo"}
        </button>
        <button
          type="button"
          className="btn"
          disabled={!canEdit || actions.length === 0}
          onClick={() => {
            setResetFrom(actions);
            setActions(eventKey, []);
          }}
        >
          Reset
        </button>
      </div>
      <p className="secondary">
        {roundsFrom !== ""
          ? `${rounds} rounds, set from the event type (${roundsFrom}). Regionals and districts run 2, championship divisions 3.`
          : "Regionals and districts run 2 rounds, championship divisions 3."}{" "}
        The log stays on this device.
      </p>
      {resetFrom && (
        <p className="notice-soft" role="status">
          Draft reset.{" "}
          <button
            type="button"
            className="btn"
            onClick={() => {
              setActions(eventKey, resetFrom);
              setResetFrom(null);
            }}
          >
            Undo reset
          </button>
        </p>
      )}

      {canEdit && picking !== null && (
        <InlineForm
          fields={[
            {
              label: "Team number for the alliance on the clock",
              digits: true,
              max: 5,
            },
          ]}
          submit="Record pick"
          validate={([value]) =>
            teamError(value ?? "", ranking) ??
            (!canInvite(board, Number(value))
              ? "This team cannot be picked now."
              : null)
          }
          onSubmit={([value]) => act(Number(value), false)}
        />
      )}

      <ol className="plain draft-alliances" aria-label="Alliances">
        {board.alliances.map((a, i) => {
          const open = allianceSize(board) - a.teams.length;
          const clock = i === picking;
          return (
            <li
              key={a.captain}
              className="draft-alliance"
              data-clock={clock ? "true" : undefined}
            >
              <span className="draft-number">{i + 1}</span>
              <span className="draft-teams">
                {a.teams.map((t) => (
                  <span key={t} className="draft-team">
                    <TeamLink team={t} />
                    {t === us && <span className="secondary">us</span>}
                  </span>
                ))}
                {open > 0 && <span className="secondary">{open} open</span>}
              </span>
              {clock && <span className="draft-on">On the clock</span>}
            </li>
          );
        })}
      </ol>

      {spare.length > 0 ? (
        <section className="pick-section" aria-labelledby="backups-h">
          <h2 id="backups-h">Backups</h2>
          <p className="secondary">
            Free teams in official ranking order, highest ranked first.
          </p>
          <ol className="plain pick-rows">
            {spare.map((team, i) => (
              <li className="pick-row" key={team}>
                <div className="pick-main">
                  <span className="pick-rank">{i + 1}</span>
                  <TeamLink team={team} />
                  <span className="secondary">
                    {statLine(facts.get(team) ?? noFacts)}
                  </span>
                </div>
              </li>
            ))}
          </ol>
        </section>
      ) : (
        <section className="pick-section" aria-labelledby="best-h">
          <h2 id="best-h">Best available</h2>
          <p className="secondary">
            Your pick list first, then seeding. Record what the alliance on the
            clock hears back.
          </p>
          <ul className="plain pick-rows">
            {free.length === 0 && (
              <li className="secondary pick-empty">
                {isComplete(board) && board.rounds === 2
                  ? "Backups show here once the official ranking loads."
                  : "No eligible teams left."}
              </li>
            )}
            {free.map((c, index) => (
              <li className="pick-row" key={c.team}>
                <div className="pick-main">
                  <TeamLink team={c.team} />
                  <span className="pick-actions">
                    <button
                      type="button"
                      className="btn"
                      disabled={!canEdit || picking === null}
                      aria-label={`${c.team} accepted`}
                      onClick={() => act(c.team, false)}
                    >
                      Accepted
                    </button>
                    <button
                      type="button"
                      className="btn"
                      disabled={!canEdit || picking === null}
                      aria-label={`${c.team} declined`}
                      onClick={() => act(c.team, true)}
                    >
                      Declined
                    </button>
                  </span>
                </div>
                <div className="pick-facts">
                  <p className="secondary">
                    {statLine(facts.get(c.team) ?? noFacts)}
                  </p>
                  {index < 3 && ours && (
                    <div>
                      <strong>For our alliance</strong>
                      <ul>
                        {allianceFit(
                          ours.teams.map((t) => facts.get(t) ?? noFacts),
                          facts.get(c.team) ?? noFacts,
                        ).map((line) => (
                          <li key={line}>{line}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                  {c.dnpReason === null ? (
                    <p className="secondary">{c.label}</p>
                  ) : (
                    <p className="pick-incidents">Do not pick: {c.dnpReason}</p>
                  )}
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}
