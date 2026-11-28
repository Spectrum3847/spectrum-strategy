import { Link } from "react-router";
import { AiRewrite } from "../assistant/AiRewrite";
import { SketchToggle } from "../board/Sketch";
import { sketchFromJson } from "../board/sketch";
import { matchLabel, matchPath } from "../data/matchKey";
import type {
  FormEntry,
  PitEntry,
  PrescoutEntry,
  TrexReport,
} from "../data/parse";
import type { EventMatch } from "../data/tbaEvent";
import { PhotoGallery } from "../photos/PhotoGallery";
import type { ScoutConfig } from "../scout/config";
import { ratingText, traitRatings } from "../trex/ratings";
import { TrexDrawing } from "../trex/TrexDrawing";
import { traitLabel } from "../trex/traits";
import { Cite } from "./Cite";
import { answersFor, type TeamComment } from "./format";
import { StatsTable } from "./StatsSection";
import type { TeamStats } from "./stats";
import {
  type CommentSummary,
  isEmptySummary,
  type SummaryLine,
} from "./summary";

export const when = (iso: string) => {
  const date = new Date(iso);
  return Number.isNaN(date.getTime())
    ? ""
    : date.toLocaleString([], {
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      });
};

const byLine = (...parts: (string | false)[]) =>
  parts.filter((p) => p !== false && p !== "").join(", ");

function outcomeText(match: EventMatch, onRed: boolean): string {
  if (match.redScore === null || match.blueScore === null) return "Not played";
  const mine = onRed ? match.redScore : match.blueScore;
  const theirs = onRed ? match.blueScore : match.redScore;
  const result =
    match.winner === null
      ? "Tied"
      : (match.winner === "red") === onRed
        ? "Won"
        : "Lost";
  return `${result} ${mine} to ${theirs}`;
}

export function MatchesSection({
  team,
  eventKey,
  matches,
  scouted,
}: {
  team: number;
  eventKey: string;
  matches: EventMatch[];
  scouted: ReadonlySet<string>;
}) {
  const mine = matches.filter(
    (m) => m.red.includes(team) || m.blue.includes(team),
  );
  return (
    <section className="team-section" aria-labelledby="team-matches">
      <h2 id="team-matches">Matches</h2>
      {mine.length === 0 ? (
        <p className="secondary">
          {eventKey === ""
            ? "No event is set. Pick one in Settings."
            : `No scheduled matches for team ${team} at ${eventKey} yet.`}
        </p>
      ) : (
        <ul className="team-list">
          {mine.map((m) => {
            const onRed = m.red.includes(team);
            return (
              <li key={m.key}>
                <Link className="team-match" to={matchPath(m.key)}>
                  <span className="team-match-label">{matchLabel(m.key)}</span>
                  <span className="tag" data-alliance={onRed ? "red" : "blue"}>
                    {onRed ? "Red" : "Blue"}
                  </span>
                  <span className="team-match-result">
                    {outcomeText(m, onRed)}
                  </span>
                  {scouted.has(m.key.toLowerCase()) && (
                    <span className="secondary">Scouted</span>
                  )}
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

export function Lines({
  title,
  lines,
}: {
  title: string;
  lines: SummaryLine[];
}) {
  if (lines.length === 0) return null;
  return (
    <div className="team-lines">
      {title !== "" && <h3 className="label">{title}</h3>}
      <ul className="team-list">
        {lines.map((line) => (
          <li key={line.text} className="team-line">
            <span>{line.text}</span>
            {line.matches.length > 0 && (
              <span className="team-cites">
                {line.matches.map((c) => (
                  <Cite key={c.key} cite={c} />
                ))}
              </span>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

export function NoteList({ notes }: { notes: TeamComment[] }) {
  return (
    <ul className="team-list">
      {notes.map((c) => (
        <li key={c.id} className="team-comment">
          <p>{c.text}</p>
          <p className="secondary team-meta">
            <span className="team-source">{c.source}</span>
            {c.matchKey && (
              <Cite
                cite={{
                  key: c.matchKey,
                  label: matchLabel(c.matchKey),
                }}
              />
            )}
            {byLine(
              c.fieldTitle !== "Comments" && c.fieldTitle,
              c.scoutName,
              when(c.updatedAt),
            )}
          </p>
          {c.strokesByPhase && (
            <SketchToggle
              surface="Scouting drawing"
              value={sketchFromJson(c.strokesByPhase)}
              phased
            />
          )}
        </li>
      ))}
    </ul>
  );
}

export function CommentsSection({
  team,
  eventKey,
  summary,
  comments,
  notes,
  entryCount,
}: {
  team: number;
  eventKey: string;
  summary: CommentSummary;
  comments: TeamComment[];
  notes: TeamComment[];
  entryCount: number;
}) {
  const trendLines = summary.trend ? [summary.trend.line] : [];
  return (
    <section className="team-section" aria-labelledby="team-comments">
      <h2 id="team-comments">Comments and notes</h2>
      {entryCount === 0 ? (
        <p className="secondary">No scouting entries for this team yet.</p>
      ) : (
        <>
          {isEmptySummary(summary) ? (
            <p className="secondary">
              Not enough scouted matches for a summary yet.
            </p>
          ) : (
            <div className="team-summary">
              <p className="secondary">
                Summary from the scout form answers, built on this device.
              </p>
              <Lines title="Trend" lines={trendLines} />
              <Lines title="Strengths" lines={summary.strengths} />
              <Lines title="Concerns" lines={summary.concerns} />
              <Lines title="Roles" lines={summary.roles} />
            </div>
          )}
          <AiRewrite team={team} eventKey={eventKey} comments={comments} />
        </>
      )}
      {notes.length === 0 ? (
        <p className="secondary">No written comments or notes yet.</p>
      ) : (
        <>
          <p className="secondary">{`${notes.length} in all, newest first.`}</p>
          <NoteList notes={notes} />
        </>
      )}
    </section>
  );
}

function Answers({
  config,
  entry,
  skip,
}: {
  config: ScoutConfig;
  entry: FormEntry;
  skip?: ReadonlySet<string>;
}) {
  const answers = answersFor(config, entry.fieldValues, skip);
  if (answers.length === 0) return null;
  return (
    <dl className="team-answers">
      {answers.map((a) => (
        <div key={a.label} className="team-answer">
          <dt>{a.label}</dt>
          <dd>{a.value}</dd>
        </div>
      ))}
    </dl>
  );
}

export function pitPhotoKeys(entries: readonly PitEntry[]): string[] {
  return [...new Set(entries.flatMap((e) => e.photoKeys))];
}

export function PitSection({
  entries,
  config,
  eventKey,
}: {
  entries: readonly PitEntry[];
  config: ScoutConfig;
  eventKey: string;
}) {
  const entry = entries[0] ?? null;
  return (
    <section className="team-section" aria-labelledby="team-pit">
      <h2 id="team-pit">Pit scouting</h2>
      {entry === null ? (
        <p className="secondary">No pit entry yet.</p>
      ) : (
        <>
          <p className="secondary">
            {byLine(
              entry.scoutName && `Scouted by ${entry.scoutName}`,
              when(entry.updatedAt),
              entry.eventKey !== "" &&
                entry.eventKey !== eventKey &&
                `from ${entry.eventKey}`,
            ) || "Pit entry"}
          </p>
          <Answers config={config} entry={entry} />
          <PhotoGallery keys={pitPhotoKeys(entries)} />
        </>
      )}
    </section>
  );
}

const prescoutKnown = new Set([
  "watchedEvent",
  "matchType",
  "matchNumber",
  "videoUrl",
  "comments",
]);

function prescoutLabel(entry: PrescoutEntry): string {
  const v = entry.fieldValues;
  const number = String(v.matchNumber ?? "").trim();
  const type = String(v.matchType ?? "");
  const match =
    number === ""
      ? ""
      : type === "qual"
        ? `Q${number}`
        : type === "playoff"
          ? `Playoff ${number}`
          : type === "final"
            ? `Final ${number}`
            : number;
  const event = String(v.watchedEvent ?? "").trim();
  return byLine(match, event) || "Watched match";
}

const safeUrl = (raw: unknown) => {
  const text = String(raw ?? "").trim();
  return /^https:\/\//i.test(text) ? text : null;
};

export function PrescoutSection({
  entries,
  stats,
  config,
  team,
}: {
  entries: PrescoutEntry[];
  stats: TeamStats;
  config: ScoutConfig;
  team: number;
}) {
  return (
    <section className="team-section" aria-labelledby="team-prescout">
      <h2 id="team-prescout">Prescout</h2>
      {entries.length === 0 ? (
        <p className="secondary">No prescout entries yet.</p>
      ) : (
        <>
          <p className="secondary">
            From watched matches at other events. Not part of the event stats.
          </p>
          <StatsTable stats={stats} caption={`Team ${team} prescout stats`} />
          <ul className="team-list">
            {entries.map((entry) => {
              const comment = String(entry.fieldValues.comments ?? "").trim();
              const video = safeUrl(entry.fieldValues.videoUrl);
              return (
                <li key={entry.id}>
                  <details className="team-details">
                    <summary>{prescoutLabel(entry)}</summary>
                    <Answers
                      config={config}
                      entry={entry}
                      skip={prescoutKnown}
                    />
                    {comment !== "" && <p>{comment}</p>}
                    <p className="secondary team-meta">
                      {byLine(entry.scoutName, when(entry.updatedAt))}
                      {video && (
                        <a href={video} target="_blank" rel="noreferrer">
                          Watch the video
                        </a>
                      )}
                    </p>
                  </details>
                </li>
              );
            })}
          </ul>
        </>
      )}
    </section>
  );
}

export function TrexSection({ reports }: { reports: TrexReport[] }) {
  const ratings = traitRatings(reports);
  return (
    <section className="team-section" aria-labelledby="team-trex">
      <h2 id="team-trex">T-REx traits</h2>
      {reports.length === 0 ? (
        <p className="secondary">No T-REx reports yet.</p>
      ) : (
        <ul className="team-list">
          {ratings.length > 0 && (
            <li>
              <ul className="plain team-ratings" aria-label="Average ratings">
                {ratings.map((r) => (
                  <li key={r.key}>
                    <strong>{r.label}:</strong> {ratingText(r)}
                  </li>
                ))}
              </ul>
            </li>
          )}
          {reports.map((r) => (
            <li key={r.id} className="team-comment">
              <p>{r.report.trim()}</p>
              <p className="secondary team-meta">
                {byLine(
                  traitLabel(r.trait),
                  r.rating !== null && `Rating ${r.rating} of 5`,
                  r.matchNumber > 0 && `Match ${r.matchNumber}`,
                  r.scoutName,
                  when(r.updatedAt),
                )}
              </p>
              <TrexDrawing report={r} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
