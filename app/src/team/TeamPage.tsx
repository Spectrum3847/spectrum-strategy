import { useMemo, useState, useSyncExternalStore } from "react";
import { Link, useParams } from "react-router";
import type { MatchScorePoint } from "../assistant/scoringTrend";
import { useAuth } from "../auth/AuthProvider";
import { canOpenPath, isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { EntriesSection } from "../corrections/EntriesSection";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { noteId } from "../data/teamNotes";
import {
  useFormConfig,
  usePitEntries,
  usePrescoutEntries,
  useTrexReports,
} from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { useTeamNotes } from "../data/useTeamNotes";
import { PickedMark } from "../picks/PickedMark";
import { useScoutData } from "../scout/ScoutData";
import { valueCounts } from "./counts";
import { allNotes, commentsFor } from "./format";
import { MatchWindow } from "./MatchWindow";
import { PickControl } from "./PickControl";
import {
  CommentsSection,
  MatchesSection,
  PitSection,
  PrescoutSection,
  TrexSection,
  when,
} from "./Sections";
import { StatsSection } from "./StatsSection";
import {
  computeStats,
  entryMatchKey,
  groupByMatch,
  matchScores,
  type StatInput,
} from "./stats";
import { buildSummary } from "./summary";
import { BriefCard, TrendCard } from "./TeamAi";
import { minTrendPoints, TrendChart } from "./TrendChart";
import { useTeamHistory } from "./useTeamHistory";
import { lastMatches } from "./window";
import "./team.css";

const subscribeOnline = (notify: () => void) => {
  window.addEventListener("online", notify);
  window.addEventListener("offline", notify);
  return () => {
    window.removeEventListener("online", notify);
    window.removeEventListener("offline", notify);
  };
};

const newest = <T extends { updatedAt: string }>(a: T, b: T) =>
  b.updatedAt.localeCompare(a.updatedAt);

export function Team() {
  const { team: param } = useParams();
  const team = /^\d+$/.test(param ?? "") ? Number(param) : 0;
  const auth = useAuth();
  const roles = useRoles();
  const online = useSyncExternalStore(
    subscribeOnline,
    () => navigator.onLine,
    () => true,
  );
  const { config, eventKey } = useScoutData();
  const entries = useCorrectedEntries(eventKey);
  const tba = useTbaEvent();
  const pit = usePitEntries();
  const prescout = usePrescoutEntries();
  const trex = useTrexReports();
  const pitConfig = useFormConfig("pit");
  const prescoutConfig = useFormConfig("prescout");

  const mine = useMemo(
    () => entries.items.filter((e) => e.teamNumber === team),
    [entries.items, team],
  );
  const inputs = useMemo<StatInput[]>(
    () =>
      mine.map((e) => ({
        id: e.id,
        matchKey: entryMatchKey(e),
        fieldValues: e.fieldValues,
      })),
    [mine],
  );
  const [last, setLast] = useState<number | null>(null);
  const scoutedMatches = useMemo(() => groupByMatch(inputs).length, [inputs]);
  const shown = useMemo(() => lastMatches(inputs, last), [inputs, last]);
  const stats = useMemo(() => computeStats(config, shown), [config, shown]);
  const summary = useMemo(
    () => buildSummary(config, groupByMatch(shown), stats),
    [config, shown, stats],
  );
  const counts = useMemo(
    () => valueCounts(config, groupByMatch(shown)),
    [config, shown],
  );
  const comments = useMemo(() => commentsFor(config, mine), [config, mine]);
  const teamNotes = useTeamNotes(eventKey);
  const lead = roles.status === "ready" && isLead(roles.roles);
  const uid = auth.status === "signed-in" ? (auth.uid ?? "") : "";
  const history = useTeamHistory(team, lead && uid !== "" && eventKey !== "");
  const trendSeries = useMemo<MatchScorePoint[]>(() => {
    const sideOf = new Map(
      tba.matches.map((m) => [
        m.key.toLowerCase(),
        m.red.includes(team) ? "Red" : m.blue.includes(team) ? "Blue" : "",
      ]),
    );
    return matchScores(config, inputs).map((m) => ({
      ...m,
      alliance: sideOf.get(m.key) ?? "",
    }));
  }, [config, inputs, tba.matches, team]);
  const scouted = useMemo(
    () =>
      new Set(
        mine.flatMap((e) =>
          e.tbaMatchKey ? [e.tbaMatchKey.toLowerCase()] : [],
        ),
      ),
    [mine],
  );

  const pitEntries = useMemo(
    () => pit.items.filter((e) => e.teamNumber === team).sort(newest),
    [pit.items, team],
  );
  const prescoutEntries = useMemo(
    () => prescout.items.filter((e) => e.teamNumber === team).sort(newest),
    [prescout.items, team],
  );
  const prescoutStats = useMemo(
    () =>
      computeStats(
        prescoutConfig,
        prescoutEntries.map((e) => ({
          id: e.id,
          matchKey: e.id,
          fieldValues: e.fieldValues,
        })),
      ),
    [prescoutConfig, prescoutEntries],
  );
  const trexReports = useMemo(
    () =>
      trex.items
        .filter(
          (r) =>
            r.teamNumber === team &&
            r.report.trim() !== "" &&
            (r.eventKey === "" || r.eventKey === eventKey),
        )
        .sort(newest),
    [trex.items, team, eventKey],
  );

  const teamNote =
    teamNotes.items.find((n) => n.id === noteId(eventKey, team)) ?? null;
  const notes = useMemo(
    () =>
      allNotes({
        scout: comments,
        pit: { config: pitConfig, entries: pitEntries },
        prescout: { config: prescoutConfig, entries: prescoutEntries },
        trex: trexReports,
        note: teamNote,
      }),
    [
      comments,
      pitConfig,
      pitEntries,
      prescoutConfig,
      prescoutEntries,
      trexReports,
      teamNote,
    ],
  );

  if (team === 0) {
    return (
      <>
        <h1>Team {param}</h1>
        <p className="secondary">That is not a team number.</p>
        <Link to="/">Back to Now</Link>
      </>
    );
  }

  const info = tba.teams.find((t) => t.number === team);
  const ranking = tba.rankings.find((r) => r.team === team);
  const signedIn = auth.status === "signed-in";
  const standing = ranking
    ? `Rank ${ranking.rank}, ${ranking.wins}-${ranking.losses}-${ranking.ties}`
    : tba.rankings.length > 0
      ? "Not ranked"
      : "";

  return (
    <div className="team">
      <header className="team-head">
        <h1>Team {team}</h1>
        {info?.nickname && <p className="team-nickname">{info.nickname}</p>}
        {standing !== "" && <p className="secondary">{standing}</p>}
        <PickedMark team={team} />
        <PickControl team={team} />
        {roles.status === "ready" &&
          canOpenPath(roles.roles, `/scout/prescout/${team}`) && (
            <Link className="btn" to={`/scout/prescout/${team}`}>
              Pre-scout
            </Link>
          )}
        {eventKey !== "" && (
          <p className="secondary">
            {byEvent(eventKey, tba.fetchedAt, tba.teams.length > 0 && !info)}
          </p>
        )}
      </header>

      {!signedIn && (
        <p className="notice" role="status">
          Sign in to load scouting data for this team.
        </p>
      )}
      {signedIn && !online && (
        <p className="secondary" role="status">
          Offline. This shows what this device last saved.
        </p>
      )}
      {signedIn && entries.failed && (
        <p className="notice" role="status">
          Could not read the latest scout entries. This may be incomplete.
        </p>
      )}
      {signedIn && entries.correctionsFailed && (
        <p className="notice" role="status">
          Could not read the latest corrections. The stats may show uncorrected
          values.
        </p>
      )}
      {signedIn &&
        eventKey !== "" &&
        tba.status === "failed" &&
        tba.fetchedAt === null && (
          <p className="secondary" role="status">
            Team names, ranks and results need a connection the first time.
          </p>
        )}
      {signedIn && eventKey === "" && (
        <p className="secondary">
          No event is set, so there are no event stats. Pick one in Settings.
        </p>
      )}

      {scoutedMatches > 0 && (
        <MatchWindow last={last} total={scoutedMatches} onChange={setLast} />
      )}

      <div className="team-columns">
        <div className="team-column">
          <StatsSection team={team} stats={stats} counts={counts} />
          <section className="team-section" aria-labelledby="team-trend">
            <h2 id="team-trend">Scoring by match</h2>
            {stats.series.length >= minTrendPoints ? (
              <>
                <TrendChart series={stats.series} />
                <TrendCard
                  team={team}
                  eventKey={eventKey}
                  series={trendSeries}
                  history={history.history}
                  loading={history.loading}
                  lead={lead}
                  uid={uid}
                />
              </>
            ) : (
              <p className="secondary">
                {`A trend needs ${minTrendPoints} scored matches. This team has ${stats.series.length}.`}
              </p>
            )}
          </section>
          <MatchesSection
            team={team}
            eventKey={eventKey}
            matches={tba.matches}
            scouted={scouted}
          />
        </div>
        <div className="team-column">
          <BriefCard
            team={team}
            history={history.history}
            loading={history.loading}
            lead={lead}
            uid={uid}
          />
          <CommentsSection
            team={team}
            eventKey={eventKey}
            summary={summary}
            comments={comments}
            notes={notes}
            entryCount={mine.length}
          />
          <PitSection
            entries={pitEntries}
            config={pitConfig}
            eventKey={eventKey}
          />
          <TrexSection reports={trexReports} />
          <PrescoutSection
            entries={prescoutEntries}
            stats={prescoutStats}
            config={prescoutConfig}
            team={team}
          />
        </div>
      </div>
      <EntriesSection
        team={team}
        eventKey={eventKey}
        config={config}
        entries={mine}
      />
    </div>
  );
}

function byEvent(eventKey: string, fetchedAt: string | null, missing: boolean) {
  return [
    eventKey,
    missing && "not on the team list",
    fetchedAt && `TBA data from ${when(fetchedAt)}`,
  ]
    .filter(Boolean)
    .join(", ");
}
