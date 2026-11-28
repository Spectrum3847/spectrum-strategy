import { useMemo } from "react";
import type { EventMatch, EventTeam, TeamRanking } from "../data/tbaEvent";
import type { ScoutData } from "../scout/ScoutData";
import type { ScheduledMatch } from "../scout/schedule";
import { eventMatchesFrom, rankingsAt, scheduleAt } from "./replay";
import { useTrainingSession } from "./session";

export interface TrainingView {
  eventKey: string;
  startedAt: string;
  schedule: ScheduledMatch[];
  matches: EventMatch[];
  teams: EventTeam[];
  rankings: TeamRanking[];
}

export function useTrainingView(): TrainingView | null {
  const session = useTrainingSession();
  return useMemo(() => {
    if (!session) return null;
    const schedule = scheduleAt(session.replay, session.revealed);
    return {
      eventKey: session.eventKey,
      startedAt: session.startedAt,
      schedule,
      matches: eventMatchesFrom(schedule),
      teams: session.replay.teams,
      rankings: rankingsAt(schedule),
    };
  }, [session]);
}

const noop = () => undefined;
const noRefresh = () => Promise.resolve();

export function useTrainingScoutData(live: ScoutData | null): ScoutData | null {
  const view = useTrainingView();
  return useMemo(
    () =>
      live && view
        ? {
            ...live,
            eventKey: view.eventKey,
            eventReady: true,
            setEventKey: noop,
            schedule: view.schedule,
            scheduleFetchedAt: view.startedAt,
            scheduleStatus: "ready",
            refreshSchedule: noRefresh,
            shifts: null,
          }
        : live,
    [live, view],
  );
}
