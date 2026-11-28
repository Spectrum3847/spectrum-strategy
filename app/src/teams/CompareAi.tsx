import { AiCard } from "../assistant/AiCard";
import { provenance } from "../assistant/queue";
import { compareKey, compareRequest } from "../assistant/teamCompare";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import type { EventEntry } from "../data/parse";
import { useScoutData } from "../scout/ScoutData";
import { compareFacts } from "./compareFacts";

export function CompareAi({
  teams,
  eventKey,
  entries,
}: {
  teams: number[];
  eventKey: string;
  entries: EventEntry[];
}) {
  const auth = useAuth();
  const roles = useRoles();
  const { config } = useScoutData();
  const lead = roles.status === "ready" && isLead(roles.roles);
  const uid = auth.status === "signed-in" ? (auth.uid ?? "") : "";
  if (!lead || uid === "" || eventKey === "") return null;
  const found = teams.map((team) => ({
    team,
    ...compareFacts(config, entries, team),
  }));
  if (found.every((f) => f.scouted === 0)) return null;
  return (
    <section className="cmp-section" aria-labelledby="cmp-ai">
      <h2 id="cmp-ai">AI summaries</h2>
      {found.map(({ team, scouted, facts }) => (
        <AiCard
          key={team}
          title={`AI summary for team ${team}`}
          askLabel={`Summarise team ${team}`}
          summaryTitle={`AI summary for team ${team}`}
          idle={`Ask a team device with an AI model to summarise team ${team} from its scouted stats and ${facts.comments.length} written comments.`}
          describe={(summary, now) =>
            `${provenance(summary, facts.comments.length, "comments", now)} Check it against the table above.`
          }
          cacheKey={compareKey(eventKey, team)}
          request={compareRequest(eventKey, team, scouted, facts)}
          lead={lead}
          uid={uid}
        />
      ))}
    </section>
  );
}
