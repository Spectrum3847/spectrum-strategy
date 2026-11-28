import { lazy, type ReactNode, Suspense, useMemo } from "react";
import { Link, useParams, useSearchParams } from "react-router";
import { useOfficialCounts } from "../accuracy/useAccuracyData";
import { useAuth } from "../auth/AuthProvider";
import { isLead, isMentorOnly } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { matchLabel, matchPath } from "../data/matchKey";
import type { EventEntry } from "../data/parse";
import {
  useFormConfig,
  usePitEntries,
  usePrescoutEntries,
  useTrexReports,
} from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { useTeamNotes } from "../data/useTeamNotes";
import { timeLine } from "../now/matches";
import { useMyTeam } from "../now/myTeam";
import { useOutbox } from "../outbox/useOutbox";
import { PostMatchSection } from "../reports/PostMatchSection";
import { useScoutData } from "../scout/ScoutData";
import { notesByTeam } from "../team/notes";
import { useTrainingSession } from "../training/session";
import { ratingsByTeam } from "../trex/ratings";
import { inEvent } from "../trex/reports";
import { useOnline } from "../ui/useOnline";
import { BriefTab } from "./BriefTab";
import { briefId, type Edit, emptyBrief, matchIdOf } from "./brief";
import { WhyPrediction, WhyResult } from "./Explain";
import { explainPrediction, explainResult } from "./explain";
import {
  Alliances,
  Comments,
  Prediction,
  Result,
  StartConflictNotice,
  StatTable,
  UnscoutedNotice,
} from "./MatchTab";
import { entriesBefore } from "./prior";
import { buildRobots, plansFor, type Side } from "./robots";
import { startConflicts, usualStarts } from "./startConflicts";
import { saveBrief, useBriefs } from "./useBriefs";
import { useEpa, useForecasts } from "./useOutside";
import { WhatIf } from "./WhatIf";
import { redWinChance, scoutedForecast } from "./whatIf";
import "./match.css";

type Tab = "match" | "brief" | "plan";

const PlanTab = lazy(() => import("../board/PlanTab"));

function Section({
  id,
  title,
  children,
}: {
  id: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="match-section" aria-labelledby={id}>
      <h2 id={id}>{title}</h2>
      {children}
    </section>
  );
}

function chanceBefore(
  red: number[],
  blue: number[],
  entries: EventEntry[],
  forecast: { redWin: number } | null,
): { redWin: number | null; chanceFrom: string } {
  if (forecast) {
    return { redWin: forecast.redWin, chanceFrom: "The Blue Alliance" };
  }
  const { forecast: ours } = scoutedForecast(red, blue, entries);
  return ours
    ? { redWin: redWinChance(ours), chanceFrom: "our scouting" }
    : { redWin: null, chanceFrom: "" };
}

export function Match() {
  const { key = "" } = useParams();
  const matchKey = key.toLowerCase();
  const [search] = useSearchParams();
  const asked = search.get("tab");
  const auth = useAuth();
  const roles = useRoles();
  const mentorOnly = roles.status === "ready" && isMentorOnly(roles.roles);
  const tab: Tab =
    asked === "brief" || asked === "plan" || asked === "match"
      ? asked
      : asked === null && mentorOnly
        ? "brief"
        : "match";
  const online = useOnline();
  const training = useTrainingSession() !== null;
  const signedIn = auth.status === "signed-in" && auth.uid !== null;
  const us = useMyTeam();
  const { config, eventKey, schedule } = useScoutData();
  const tba = useTbaEvent();
  const entries = useCorrectedEntries(eventKey);
  const pit = usePitEntries();
  const pitConfig = useFormConfig("pit");
  const prescout = usePrescoutEntries();
  const prescoutConfig = useFormConfig("prescout");
  const teamNotes = useTeamNotes(eventKey);
  const trex = useTrexReports();
  const epa = useEpa(eventKey);
  const forecasts = useForecasts(eventKey);
  const briefs = useBriefs();
  const outbox = useOutbox();

  const at = tba.matches.findIndex((m) => m.key.toLowerCase() === matchKey);
  const match = tba.matches[at] ?? null;
  const played =
    match !== null && match.redScore !== null && match.blueScore !== null;
  const official = useOfficialCounts(eventKey, signedIn && !training && played);
  const previous = at > 0 ? tba.matches[at - 1] : null;
  const next = at >= 0 ? (tba.matches[at + 1] ?? null) : null;

  const nicknames = useMemo(
    () => new Map(tba.teams.map((t) => [t.number, t.nickname])),
    [tba.teams],
  );
  const rows = useMemo(
    () =>
      match
        ? buildRobots({
            config,
            pitConfig,
            matchKey,
            red: match.red,
            blue: match.blue,
            entries: entries.items,
            pit: pit.items,
            nicknames,
            epa: epa.data,
          })
        : [],
    [
      match,
      config,
      pitConfig,
      matchKey,
      entries.items,
      pit.items,
      nicknames,
      epa.data,
    ],
  );

  const priorEntries = useMemo(
    () =>
      match && played ? entriesBefore(entries.items, match.key) : entries.items,
    [match, played, entries.items],
  );
  const priorRows = useMemo(
    () =>
      match && played
        ? buildRobots({
            config,
            pitConfig,
            matchKey,
            red: match.red,
            blue: match.blue,
            entries: priorEntries,
            pit: pit.items,
            nicknames,
            epa: epa.data,
          })
        : rows,
    [
      match,
      played,
      rows,
      config,
      pitConfig,
      matchKey,
      priorEntries,
      pit.items,
      nicknames,
      epa.data,
    ],
  );

  const briefTab = tab === "brief";
  const plans = useMemo(
    () => (briefTab ? plansFor(config, rows) : new Map()),
    [briefTab, config, rows],
  );
  const notes = useMemo(
    () =>
      !briefTab
        ? new Map()
        : notesByTeam({
            teams: rows.map((r) => r.team),
            eventKey,
            config,
            entries: entries.items,
            pit: { config: pitConfig, entries: pit.items },
            prescout: { config: prescoutConfig, entries: prescout.items },
            trex: trex.items,
            notes: teamNotes.items,
          }),
    [
      briefTab,
      rows,
      eventKey,
      config,
      entries.items,
      pitConfig,
      pit.items,
      prescoutConfig,
      prescout.items,
      trex.items,
      teamNotes.items,
    ],
  );

  const clashes = useMemo(() => {
    if (!match) return [];
    const side = match.red.includes(us ?? -1)
      ? "red"
      : match.blue.includes(us ?? -1)
        ? "blue"
        : null;
    const usual = usualStarts(config, entries.items, [
      ...match.red,
      ...match.blue,
    ]);
    return [
      ...(side === "blue" ? [] : startConflicts(match.red, usual)),
      ...(side === "red" ? [] : startConflicts(match.blue, usual)),
    ];
  }, [match, us, config, entries.items]);

  const ratings = useMemo(
    () => ratingsByTeam(trex.items.filter((r) => inEvent(r, eventKey))),
    [trex.items, eventKey],
  );

  if (match === null) {
    const waiting =
      eventKey !== "" && (tba.status === "loading" || tba.status === "none");
    return (
      <div className="match">
        <h1>Match {key}</h1>
        <p className="secondary">
          {eventKey === ""
            ? "No event is set. Pick one in Settings."
            : waiting
              ? "Loading the match schedule."
              : `${key} is not on the schedule for ${eventKey}.`}
        </p>
        <Link to="/">Back to Now</Link>
      </div>
    );
  }

  const label = matchLabel(match.key);
  const scheduled = schedule.find((m) => m.key.toLowerCase() === matchKey);
  const time = scheduled ? timeLine(scheduled, new Date()) : null;
  const ours: Side | null =
    us === null
      ? null
      : match.red.includes(us)
        ? "red"
        : match.blue.includes(us)
          ? "blue"
          : null;
  const forecast =
    forecasts.data?.[match.key] ?? forecasts.data?.[matchKey] ?? null;
  const predictionWhy =
    tab === "match"
      ? explainPrediction({
          red: match.red,
          blue: match.blue,
          entries: priorEntries,
          epa: epa.data,
          tba: forecast,
        })
      : null;
  const resultWhy =
    tab === "match" && played
      ? explainResult({
          config,
          matchKey: match.key,
          red: match.red,
          blue: match.blue,
          redScore: match.redScore ?? 0,
          blueScore: match.blueScore ?? 0,
          entries: entries.items,
          breakdown: official.alliances,
          ...chanceBefore(match.red, match.blue, priorEntries, forecast),
          tba: forecast,
          trex: trex.items.filter((r) => inEvent(r, eventKey)),
        })
      : null;

  const matchId = matchIdOf(eventKey, match.key);
  const id = briefId(eventKey, matchId);
  const brief =
    briefs.items.find((b) => b.id === id) ?? emptyBrief(eventKey, matchId);
  const sent = outbox.find((i) => i.path === `matchBriefs/${id}`);
  const lead = roles.status === "ready" && isLead(roles.roles);
  const author = {
    uid: auth.uid ?? "",
    displayName:
      (roles.status === "ready" ? roles.displayName : "") ||
      auth.displayName ||
      "",
  };
  const onSave = async (edit: Edit) => {
    await saveBrief(brief, edit, author, `Brief for ${label}`);
  };

  const to = (key: string) =>
    `${matchPath(key)}${tab === "match" && !mentorOnly ? "" : `?tab=${tab}`}`;

  return (
    <div className="match">
      <header className="match-head">
        <div className="match-title">
          <h1>{label}</h1>
          <span className="match-status">{played ? "Played" : "Upcoming"}</span>
          {ours && (
            <span className="match-us">
              We play{" "}
              <span className="tag" data-alliance={ours}>
                {ours === "red" ? "Red" : "Blue"}
              </span>
            </span>
          )}
        </div>
        <p className="secondary">
          {[eventKey, time].filter((p) => p).join(", ")}
        </p>
        <nav className="match-step" aria-label="Step between matches">
          {previous ? (
            <Link className="btn" to={to(previous.key)} rel="prev">
              Previous: {matchLabel(previous.key)}
            </Link>
          ) : (
            <span className="btn" aria-disabled="true">
              Previous
            </span>
          )}
          {next ? (
            <Link className="btn" to={to(next.key)} rel="next">
              Next: {matchLabel(next.key)}
            </Link>
          ) : (
            <span className="btn" aria-disabled="true">
              Next
            </span>
          )}
        </nav>
        <nav className="match-tabs" aria-label="Match sections">
          <Link
            className="btn"
            to={{ search: mentorOnly ? "?tab=match" : "" }}
            replace
            aria-current={tab === "match" ? "page" : undefined}
          >
            Match
          </Link>
          {lead && (
            <Link
              className="btn"
              to="?tab=plan"
              replace
              aria-current={tab === "plan" ? "page" : undefined}
            >
              Plan
            </Link>
          )}
          <Link
            className="btn"
            to="?tab=brief"
            replace
            aria-current={tab === "brief" ? "page" : undefined}
          >
            Brief
          </Link>
        </nav>
      </header>

      {!online && (
        <p className="notice-soft" role="status">
          Offline. This shows what this device last saved.
        </p>
      )}
      {entries.failed && (
        <p className="notice" role="status">
          Could not read the latest scout entries. This may be incomplete.
        </p>
      )}

      {entries.correctionsFailed && (
        <p className="notice" role="status">
          Could not read the latest corrections. The stats may show uncorrected
          values.
        </p>
      )}

      {tab === "match" ? (
        <>
          <UnscoutedNotice rows={rows} />
          <StartConflictNotice conflicts={clashes} />
          <Alliances rows={rows} us={us} />
          <Section id="stats-h" title="Scouted stats">
            <StatTable rows={rows} us={us} />
          </Section>
          <Section id="predict-h" title="Prediction">
            <Prediction
              rows={priorRows}
              epa={epa}
              forecast={forecast}
              forecasts={forecasts}
            />
          </Section>
          {predictionWhy && (
            <Section id="why-predict-h" title="Why this prediction">
              <WhyPrediction why={predictionWhy} before={played} />
            </Section>
          )}
          <Section id="whatif-h" title="What if">
            <WhatIf
              key={match.key}
              red={match.red}
              blue={match.blue}
              config={config}
              pitConfig={pitConfig}
              entries={entries.items}
              pit={pit.items}
              nicknames={nicknames}
              epa={epa.data}
            />
          </Section>
          {played && (
            <Section id="result-h" title="Result">
              <Result match={match} rows={rows} />
            </Section>
          )}
          {resultWhy && (
            <Section id="why-result-h" title="Why this result">
              <WhyResult
                why={resultWhy}
                breakdownLoaded={official.alliances.some(
                  (a) => a.matchKey.toLowerCase() === matchKey,
                )}
              />
            </Section>
          )}
          {played && (
            <PostMatchSection
              eventKey={eventKey}
              matchKey={match.key}
              label={label}
              canEdit={lead}
              signedIn={signedIn}
              author={author}
              match={match}
              us={us}
            />
          )}
          <Section id="comments-h" title="Latest scout comments">
            <Comments rows={rows} />
          </Section>
        </>
      ) : tab === "plan" ? (
        lead ? (
          <>
            <p className="secondary">
              <Link to="/boards">All boards</Link>, practice matches and boards
              teammates drew.
            </p>
            <Suspense
              fallback={
                <p className="secondary" role="status">
                  Loading the board
                </p>
              }
            >
              <PlanTab
                eventKey={eventKey}
                matchKey={match.key}
                red={match.red}
                blue={match.blue}
                ours={ours}
                label={label}
              />
            </Suspense>
          </>
        ) : (
          <p className="secondary">The strategy board is for strategy leads.</p>
        )
      ) : (
        <BriefTab
          rows={rows}
          brief={brief}
          config={config}
          plans={plans}
          loaded={entries.ready}
          notes={notes}
          ours={ours}
          forecast={forecast}
          ratings={ratings}
          canEdit={lead}
          canSave={signedIn}
          delivery={
            sent
              ? {
                  status: sent.status,
                  ...(sent.error ? { error: sent.error } : {}),
                }
              : undefined
          }
          signedIn={signedIn}
          onSave={onSave}
        />
      )}
    </div>
  );
}
