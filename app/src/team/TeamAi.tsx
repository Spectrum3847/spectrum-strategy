import { AiCard } from "../assistant/AiCard";
import { provenance } from "../assistant/queue";
import {
  type MatchScorePoint,
  trendKey,
  trendRequest,
} from "../assistant/scoringTrend";
import { briefKey, briefRequest, minimumEvents } from "../assistant/teamBrief";
import type { TeamHistory } from "./history";

interface Access {
  lead: boolean;
  uid: string;
  eventKey: string;
}

const years = (history: TeamHistory) =>
  [
    ...new Set([
      ...history.seasons.map((s) => s.year),
      ...history.events.map((e) => e.year),
    ]),
  ].sort((a, b) => b - a);

const span = (list: number[]) =>
  list.length === 0
    ? ""
    : list.length === 1
      ? ` in ${list[0]}`
      : ` in ${list.slice(0, -1).join(", ")} and ${list.at(-1)}`;

const awardText = (count: number) =>
  count === 0 ? "no awards" : count === 1 ? "1 award" : `${count} awards`;

export function BriefCard({
  team,
  history,
  loading,
  lead,
  uid,
}: {
  team: number;
  history: TeamHistory;
  loading: boolean;
} & Omit<Access, "eventKey">) {
  const request = briefRequest(team, history);
  const events = history.events.length;
  return (
    <AiCard
      title="AI brief from previous events"
      askLabel="Write the brief"
      idle={`Public results: ${events} events${span(years(history))}, ${awardText(history.awards.length)}. Ask a team device with an AI model to write a brief.`}
      describe={(summary, now) =>
        `${provenance(summary, events, "events", now)} Written from public results. Check any warning against the event it names before repeating it.`
      }
      cacheKey={
        loading || events < minimumEvents
          ? null
          : briefKey(team, history.events)
      }
      request={request}
      lead={lead}
      uid={uid}
    />
  );
}

export function TrendCard({
  team,
  eventKey,
  series,
  history,
  loading,
  lead,
  uid,
}: {
  team: number;
  series: MatchScorePoint[];
  history: TeamHistory;
  loading: boolean;
} & Access) {
  const request = trendRequest(eventKey, team, series, history.seasons);
  return (
    <AiCard
      title="AI scoring trend"
      askLabel="Explain the trend"
      idle={`${series.length} matches at this event. Ask a team device with an AI model to explain the trend.`}
      describe={(summary, now) =>
        `${provenance(summary, series.length, "matches", now)} Check it against the chart above.`
      }
      cacheKey={
        loading || eventKey === "" || request === null
          ? null
          : trendKey(eventKey, team, history.seasons)
      }
      request={request}
      lead={lead}
      uid={uid}
    />
  );
}
