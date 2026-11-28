import { AiRewrite } from "../assistant/AiRewrite";
import { matchLabel } from "../data/matchKey";
import type { EventMatch } from "../data/tbaEvent";
import { GripIcon } from "../picks/parts";
import { formatStat } from "../team/format";
import type { TeamRow } from "../teams/rows";
import { TeamLink } from "../ui/TeamLink";
import type { Source } from "./board";
import type { CardColor, PanelFacts } from "./derive";
import type { CellDrag } from "./drag";
import type { QualVideos } from "./videos";

const dash = (n: number | null) => (n === null ? "--" : formatStat(n));

export function RankedList({
  rows,
  editable,
  drag,
  moving,
  onPick,
}: {
  rows: TeamRow[];
  editable: boolean;
  drag: CellDrag;
  moving: Source | null;
  onPick(team: number): void;
}) {
  return (
    <section className="pl-section" aria-labelledby="pl-ranked-h">
      <h2 id="pl-ranked-h">Ranked teams</h2>
      <p className="secondary">
        Scouted teams by average match total, best first.
        {editable && " Drag a team onto the board, or tap its grip."}
      </p>
      {rows.length === 0 ? (
        <p className="secondary">
          No scouted teams yet. The list fills in as entries come in.
        </p>
      ) : (
        <div className="pl-scroll" tabIndex={-1}>
          <table className="pl-ranked">
            <thead>
              <tr>
                {editable && (
                  <th scope="col">
                    <span className="pl-sr">Move</span>
                  </th>
                )}
                <th scope="col">#</th>
                <th scope="col">Team</th>
                <th scope="col" className="pl-num">
                  TBA rank
                </th>
                <th scope="col" className="pl-num">
                  Avg auto
                </th>
                <th scope="col" className="pl-num">
                  Avg teleop
                </th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r, i) => {
                const held = moving?.kind === "team" && moving.team === r.team;
                const source: Source = { kind: "team", team: r.team };
                return (
                  <tr
                    key={r.team}
                    data-picked={
                      held ||
                      (drag.dragging?.kind === "team" &&
                        drag.dragging.team === r.team)
                        ? "true"
                        : undefined
                    }
                  >
                    {editable && (
                      <td>
                        <button
                          type="button"
                          className="pl-handle"
                          data-handle={`team-${r.team}`}
                          aria-label={
                            held ? `Put down ${r.team}` : `Move ${r.team}`
                          }
                          aria-pressed={held}
                          onClick={() => {
                            if (drag.wasDrag()) return;
                            onPick(r.team);
                          }}
                          {...drag.handlers(source, `team-${r.team}`)}
                        >
                          <GripIcon />
                        </button>
                      </td>
                    )}
                    <td>{i + 1}</td>
                    <td>
                      <TeamLink team={r.team} />
                      {r.nickname !== "" && (
                        <span className="secondary pl-nick"> {r.nickname}</span>
                      )}
                    </td>
                    <td className="pl-num">
                      {r.rank === null ? "--" : `#${r.rank}`}
                    </td>
                    <td className="pl-num">{dash(r.mean.auto)}</td>
                    <td className="pl-num">{dash(r.mean.teleop)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

export function TeamNumbers({
  title,
  teams,
  empty,
}: {
  title: string;
  teams: number[];
  empty: string;
}) {
  return (
    <section className="pl-panel" aria-label={title}>
      <h3>{title}</h3>
      {teams.length === 0 ? (
        <p className="secondary">{empty}</p>
      ) : (
        <ul className="plain pl-teams">
          {teams.map((t) => (
            <li key={t}>
              <TeamLink team={t} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export function VideoList({
  matches,
  videos,
}: {
  matches: EventMatch[];
  videos: QualVideos;
}) {
  const quals = matches.filter((m) => m.level === "qm");
  return (
    <section className="pl-panel" aria-label="Qualification video">
      <h3>Qualification video</h3>
      {videos.status === "failed" && (
        <p className="secondary" role="status">
          Videos need a connection the first time.
        </p>
      )}
      {videos.status === "loading" && (
        <p className="secondary" role="status">
          Loading videos.
        </p>
      )}
      {quals.length === 0 ? (
        <p className="secondary">No qualification schedule yet.</p>
      ) : (
        <ul className="plain pl-videos">
          {quals.map((m) => {
            const url = videos.videos[m.key];
            const label = matchLabel(m.key);
            return (
              <li key={m.key}>
                <span>{label}</span>
                {url ? (
                  <a
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    aria-label={`Watch ${label}`}
                  >
                    Watch
                  </a>
                ) : (
                  <span className="secondary">No video</span>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

const cardText: Record<CardColor, string> = {
  red: "Red card",
  yellow: "Yellow card",
  unknown: "Card",
};

export interface Panel {
  team: number;
  nickname: string;
  card: CardColor | undefined;
  facts: PanelFacts;
}

function Lines({ title, lines }: { title: string; lines: string[] }) {
  if (lines.length === 0) return null;
  return (
    <>
      <h4>{title}</h4>
      <ul className="plain pl-lines">
        {lines.map((l) => (
          <li key={l}>{l}</li>
        ))}
      </ul>
    </>
  );
}

const recent = 3;

export function NextUp({
  panels,
  eventKey,
  boardEmpty,
}: {
  panels: Panel[];
  eventKey: string;
  boardEmpty: boolean;
}) {
  return (
    <section className="pl-section" aria-labelledby="pl-next-h">
      <h2 id="pl-next-h">Next up on the sorting board</h2>
      {panels.length === 0 ? (
        <p className="secondary">
          {boardEmpty
            ? "Fill in the sorting board and its first three teams show up here."
            : "Every team on the sorting board is already in an alliance."}
        </p>
      ) : (
        <div className="pl-panels">
          {panels.map((p) => (
            <article
              key={p.team}
              className="pl-panel"
              data-card={p.card}
              aria-label={`Team ${p.team}`}
            >
              <h3>
                <TeamLink team={p.team} />
                {p.card && <span className="pl-card">{cardText[p.card]}</span>}
              </h3>
              {p.nickname !== "" && <p className="secondary">{p.nickname}</p>}
              <dl className="pl-stats">
                <dt>Avg auto</dt>
                <dd>{dash(p.facts.avgAuto)}</dd>
                <dt>Avg teleop</dt>
                <dd>{dash(p.facts.avgTeleop)}</dd>
                <dt>Matches scouted</dt>
                <dd>{p.facts.matches}</dd>
              </dl>
              <h4>Pit scouting</h4>
              <p className="secondary">
                {p.facts.robotType === ""
                  ? "No pit entry yet."
                  : p.facts.robotType}
              </p>
              {p.facts.driveCoach !== "" && (
                <p className="secondary">Drive coach: {p.facts.driveCoach}</p>
              )}
              <Lines title="Strengths" lines={p.facts.strengths} />
              <Lines title="Concerns" lines={p.facts.concerns} />
              {p.facts.comments.length > 0 && (
                <>
                  <h4>Latest comments</h4>
                  <ul className="plain pl-lines">
                    {p.facts.comments.slice(0, recent).map((c) => (
                      <li key={c.id}>{c.text}</li>
                    ))}
                  </ul>
                  <AiRewrite
                    team={p.team}
                    eventKey={eventKey}
                    comments={p.facts.comments}
                  />
                </>
              )}
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
