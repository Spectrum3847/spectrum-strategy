import type { ReactNode } from "react";
import { Link } from "react-router";
import { TeamLink } from "../ui/TeamLink";
import { awayText, formatTime, timeLine } from "./matches";
import { recordText } from "./rankings";
import type { NowSummary, OurMatch, ShiftSummary } from "./summary";
import type { RankState } from "./useRank";
import "./now.css";

export function Section({
  id,
  title,
  children,
}: {
  id: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="now-section" aria-labelledby={id}>
      <h2 id={id}>{title}</h2>
      {children}
    </section>
  );
}

function Alliance({
  alliance,
  caption,
  teams,
  us,
}: {
  alliance: "Red" | "Blue";
  caption: string;
  teams: number[];
  us: number;
}) {
  return (
    <div className="alliance">
      <span className="tag" data-alliance={alliance.toLowerCase()}>
        {alliance}
      </span>
      <span className="alliance-caption">{caption}</span>
      <ul className="plain alliance-teams">
        {teams.map((team) => (
          <li key={team} data-us={team === us}>
            <TeamLink team={team} />
            {team === us && <span className="us">us</span>}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function NextMatch({
  next,
  team,
  now,
  prep,
  extra,
}: {
  next: OurMatch;
  team: number;
  now: Date;
  prep: { primary: boolean } | null;
  extra?: ReactNode;
}) {
  const time = timeLine(next.match, now);
  const other = next.alliance === "Red" ? "Blue" : "Red";
  return (
    <Section id="next-h" title="Our next match">
      <p className="now-label">
        {next.label}
        <span className="now-away">{awayText(next.away)}</span>
      </p>
      {time && <p className="secondary">{time}</p>}
      <Alliance
        alliance={next.alliance}
        caption="Our alliance"
        teams={next.ourSide}
        us={team}
      />
      <Alliance
        alliance={other}
        caption="Opponents"
        teams={next.opponents}
        us={team}
      />
      {extra}
      {prep && (
        <div className="actions">
          <Link
            className={prep.primary ? "btn primary" : "btn"}
            to={`/matches/${next.match.key}`}
          >
            Prep
          </Link>
          {extra && (
            <Link className="btn" to={`/matches/${next.match.key}?tab=brief`}>
              Brief
            </Link>
          )}
        </div>
      )}
    </Section>
  );
}

export function LaterMatches({
  later,
  team,
  now,
  linkMatches,
}: {
  later: OurMatch[];
  team: number;
  now: Date;
  linkMatches: boolean;
}) {
  if (later.length === 0) return null;
  return (
    <Section id="later-h" title="Our later matches">
      <ol className="plain later">
        {later.map((m) => {
          const time = timeLine(m.match, now);
          return (
            <li key={m.match.key}>
              <div className="later-main">
                {linkMatches ? (
                  <Link className="later-label" to={`/matches/${m.match.key}`}>
                    {m.label}
                  </Link>
                ) : (
                  <span className="later-label">{m.label}</span>
                )}
                <span className="tag" data-alliance={m.alliance.toLowerCase()}>
                  {m.alliance}
                </span>
                <span className="secondary">{awayText(m.away)}</span>
              </div>
              {time && <p className="secondary">{time}</p>}
              <p className="later-with">
                <span className="secondary">With</span>
                {m.ourSide
                  .filter((t) => t !== team)
                  .map((t) => (
                    <TeamLink key={t} team={t} />
                  ))}
              </p>
            </li>
          );
        })}
      </ol>
    </Section>
  );
}

export function RankRecord({
  rank,
  summary,
  now,
}: {
  rank: RankState;
  summary: Extract<NowSummary, { state: "ready" }>;
  now: Date;
}) {
  const r = rank.rank;
  return (
    <Section id="rank-h" title="Rank and record">
      {r ? (
        <>
          <p className="now-label">
            Rank {r.rank} of {r.of}
          </p>
          <p>
            Record {recordText(r)} (wins, losses, ties) after {r.played}{" "}
            {r.played === 1 ? "match" : "matches"}.
          </p>
          {rank.fetchedAt && (
            <p className="secondary">
              Updated {formatTime(Date.parse(rank.fetchedAt) / 1000, now)}
            </p>
          )}
        </>
      ) : (
        <p className="secondary">
          {rank.status === "failed"
            ? "Rankings could not be loaded."
            : rank.status === "loading"
              ? "Loading rankings."
              : "The Blue Alliance has no ranking for this team yet. It posts rankings after the first qualification matches."}
        </p>
      )}
      <p className="secondary">
        Played {summary.playedCount} of {summary.totalCount} scheduled matches.
      </p>
    </Section>
  );
}

export function Scouting({
  shift,
  primary,
}: {
  shift: ShiftSummary;
  primary: boolean;
}) {
  const start = (
    <div className="actions">
      <Link className={primary ? "btn primary" : "btn"} to="/scout">
        {primary ? "Start" : "Open Scout"}
      </Link>
      <Link className="btn" to="/scout/shifts">
        Scouting shifts
      </Link>
    </div>
  );
  if (shift.status !== "next") {
    const text = {
      "no-grid": "No scouting shifts are set up for this event yet.",
      "not-scheduled": "No scouting shift is assigned to you.",
      done: "Your scouting shifts are finished.",
    }[shift.status];
    return (
      <Section id="scouting-h" title="Your scouting">
        <p>{text}</p>
        {start}
      </Section>
    );
  }
  const { block, away } = shift;
  const range =
    block.startMatch === block.endMatch
      ? `Q${block.startMatch}`
      : `Q${block.startMatch} to Q${block.endMatch}`;
  return (
    <Section id="scouting-h" title="Your scouting">
      <p className="now-label">
        {range}
        <span className="now-away">
          {away === 0 ? "On duty now" : awayText(away)}
        </span>
      </p>
      {block.station && <p className="secondary">Station {block.station}</p>}
      {start}
    </Section>
  );
}
