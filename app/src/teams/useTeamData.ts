import { useMemo } from "react";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { useTbaEvent } from "../data/useTbaEvent";
import { useEpa } from "../match/useOutside";
import { useTaken } from "../picks/draftStore";
import { useScoutData } from "../scout/ScoutData";
import { buildRows } from "./rows";

export function useTeamData() {
  const { config, eventKey, eventReady } = useScoutData();
  const tba = useTbaEvent();
  const entries = useCorrectedEntries(eventKey);
  const epa = useEpa(eventKey);
  const taken = useTaken(eventKey);
  const rows = useMemo(
    () =>
      buildRows({
        config,
        teams: tba.teams,
        rankings: tba.rankings,
        entries: entries.items,
        epa: epa.data,
      }),
    [config, tba.teams, tba.rankings, entries.items, epa.data],
  );
  return { config, eventKey, eventReady, tba, entries, epa, taken, rows };
}
