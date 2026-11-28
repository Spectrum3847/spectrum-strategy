import { useMemo } from "react";
import { useMyTeam } from "../now/myTeam";
import { buildNow } from "../now/summary";
import { useScoutData } from "../scout/ScoutData";
import { commentsFor } from "../team/format";
import { useTeamData } from "../teams/useTeamData";
import type { Facts } from "./chat";

export function useChatFacts(): Facts {
  const { eventKey, rows, entries } = useTeamData();
  const { config, schedule } = useScoutData();
  const team = useMyTeam();
  return useMemo(() => {
    const now = buildNow(schedule, team);
    const next = now.state === "ready" ? now.next : null;
    return {
      eventKey,
      team,
      rows,
      next: next && {
        label: next.label,
        alliance: next.alliance,
        ours: next.ourSide,
        opponents: next.opponents,
      },
      commentsOf: (t: number) =>
        commentsFor(
          config,
          entries.items.filter((e) => e.teamNumber === t),
        ).map((c) => c.text),
    };
  }, [eventKey, rows, entries.items, config, schedule, team]);
}
