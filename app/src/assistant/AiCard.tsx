import { useTrainingSession } from "../training/session";
import { useOnline } from "../ui/useOnline";
import { type AssistantApi, firestoreApi } from "./firestore";
import { type AiSummary, type AssistantRequest, sharedWaitMs } from "./queue";
import { useAiSummary } from "./useAiSummary";
import "./assistant.css";

const minutes = sharedWaitMs / 60_000;

interface Props {
  title: string;
  askLabel?: string;
  summaryTitle?: string;
  idle: string;
  describe: (summary: AiSummary, nowMs: number) => string;
  cacheKey: string | null;
  request: AssistantRequest | null;
  lead: boolean;
  uid: string;
  api?: AssistantApi;
}

export function AiCard({
  title,
  askLabel = title,
  summaryTitle = "AI-written summary",
  idle,
  describe,
  cacheKey,
  request,
  lead,
  uid,
  api = firestoreApi,
}: Props) {
  const online = useOnline();
  const training = useTrainingSession() !== null;
  const { summary, status, error, ready, ask } = useAiSummary({
    api,
    cacheKey,
    uid,
    request,
  });

  if (!lead || uid === "" || cacheKey === null || training) return null;
  if (summary) {
    return (
      <div className="team-ai">
        <h3 className="label">{summaryTitle}</h3>
        <p className="team-ai-text">{summary.text}</p>
        <p className="secondary">{describe(summary, Date.now())}</p>
      </div>
    );
  }
  if (request === null) return null;

  const busy = status === "sending" || status === "waiting";
  if (status === "idle" && !online) return null;
  return (
    <div className="team-ai">
      <h3 className="label">{title}</h3>
      {status === "idle" && (
        <p className="secondary">{`${idle} It can take up to ${minutes} minutes.`}</p>
      )}
      {status === "sending" && (
        <p className="secondary" role="status">
          Sending the request.
        </p>
      )}
      {status === "waiting" && (
        <p className="secondary" role="status">
          {`Request sent. Waiting for a team device with an AI model to answer, up to ${minutes} minutes.`}
        </p>
      )}
      {status === "failed" && (
        <p className="notice" role="status">
          {`Could not send the request. ${error}`}
        </p>
      )}
      {status === "unavailable" && (
        <p className="notice-soft" role="status">
          {`The AI path is not available. No team device with an AI model answered in ${minutes} minutes. Open the app on a laptop or iPhone with an AI model, then try again.`}
        </p>
      )}
      {!busy && online && (
        <div className="actions">
          <button type="button" className="btn" disabled={!ready} onClick={ask}>
            {status === "failed" || status === "unavailable"
              ? "Try again"
              : askLabel}
          </button>
        </div>
      )}
    </div>
  );
}
