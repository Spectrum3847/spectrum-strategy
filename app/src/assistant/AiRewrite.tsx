import { useMemo } from "react";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { matchLabel } from "../data/matchKey";
import type { TeamComment } from "../team/format";
import { AiCard } from "./AiCard";
import { type DigestNote, digestKey, digestRequest } from "./digest";
import type { AssistantApi } from "./firestore";
import { provenance } from "./queue";

const notesOf = (comments: TeamComment[]): DigestNote[] =>
  comments.map((c) => ({
    match: c.matchKey ? matchLabel(c.matchKey) : "",
    author: c.scoutName,
    text: c.text,
  }));

interface Props {
  team: number;
  eventKey: string;
  comments: TeamComment[];
  api?: AssistantApi;
}

export function AiRewrite({ team, eventKey, comments, api }: Props) {
  const auth = useAuth();
  const roles = useRoles();
  const uid = auth.status === "signed-in" ? (auth.uid ?? "") : "";
  const request = useMemo(
    () => digestRequest(eventKey, team, notesOf(comments)),
    [eventKey, team, comments],
  );
  return (
    <AiCard
      title="AI comment summary"
      idle={`Ask a team device with an AI model to summarise the ${comments.length} written comments.`}
      describe={(summary, now) =>
        `${provenance(summary, comments.length, "comments", now)} Check it against the comments below.`
      }
      cacheKey={
        eventKey === "" || request === null ? null : digestKey(eventKey, team)
      }
      request={request}
      lead={roles.status === "ready" && isLead(roles.roles)}
      uid={uid}
      {...(api && { api })}
    />
  );
}
