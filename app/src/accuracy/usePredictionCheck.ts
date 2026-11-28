import { useMemo } from "react";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { useTbaEvent } from "../data/useTbaEvent";
import { useForecasts } from "../match/useOutside";
import { useMyTeam } from "../now/myTeam";
import { useScoutData } from "../scout/ScoutData";
import {
  buildCheck,
  type Check,
  calledByScouting,
  calledByTba,
  type Source,
} from "./predictionCheck";

export function usePredictionCheck(): {
  eventKey: string;
  ready: boolean;
  checks: Record<Source, Check>;
  firstWithMatches: Source;
} {
  const { eventKey } = useScoutData();
  const tba = useTbaEvent();
  const forecasts = useForecasts(eventKey);
  const entries = useCorrectedEntries(eventKey);
  const us = useMyTeam();
  const checks = useMemo(() => {
    const played = tba.matches.filter(
      (m) => m.redScore !== null && m.blueScore !== null,
    );
    return {
      tba: buildCheck(calledByTba(played, forecasts.data), us),
      scouting: buildCheck(calledByScouting(played, entries.items), us),
    };
  }, [tba.matches, forecasts.data, entries.items, us]);
  return {
    eventKey,
    ready: entries.ready && tba.status !== "loading",
    checks,
    firstWithMatches: checks.tba.n > 0 ? "tba" : "scouting",
  };
}
