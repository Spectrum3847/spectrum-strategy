import { useCallback, useEffect, useRef, useState } from "react";
import type { AssistantApi } from "./firestore";
import {
  type AiSummary,
  type AssistantRequest,
  cacheDocId,
  minimumChars,
  parseSummary,
  requestDoc,
  sharedWaitMs,
} from "./queue";

export type AiStatus =
  | "idle"
  | "sending"
  | "waiting"
  | "failed"
  | "unavailable";

export interface AiSummaryState {
  summary: AiSummary | null;
  status: AiStatus;
  error: string;
  ready: boolean;
  ask(): void;
}

export const sendWaitMs = 15_000;

interface Options {
  api: AssistantApi;
  cacheKey: string | null;
  uid: string;
  request: AssistantRequest | null;
  minChars?: number;
  waitMs?: number;
  sendMs?: number;
}

function sent(write: Promise<void>, ms: number): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error("The database did not answer.")),
      ms,
    );
  });
  return Promise.race([write, late]).finally(() => clearTimeout(timer));
}

export function useAiSummary({
  api,
  cacheKey,
  uid,
  request,
  minChars = minimumChars,
  waitMs = sharedWaitMs,
  sendMs = sendWaitMs,
}: Options): AiSummaryState {
  const [summary, setSummary] = useState<AiSummary | null>(null);
  const [docId, setDocId] = useState<string | null>(null);
  const [state, setState] = useState<{ status: AiStatus; error: string }>({
    status: "idle",
    error: "",
  });
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const inFlight = useRef(false);
  const minimum = useRef(minChars);
  minimum.current = minChars;

  // biome-ignore lint/correctness/useExhaustiveDependencies: api is a constant in the app
  useEffect(() => {
    let stop: (() => void) | undefined;
    let live = true;
    setSummary(null);
    setDocId(null);
    setState({ status: "idle", error: "" });
    inFlight.current = false;
    if (cacheKey !== null) {
      cacheDocId(cacheKey)
        .then((id) => {
          if (!live) return;
          setDocId(id);
          stop = api.watchSummary(id, (data) =>
            setSummary(data ? parseSummary(data, minimum.current) : null),
          );
        })
        .catch(() => undefined);
    }
    return () => {
      live = false;
      stop?.();
      clearTimeout(timer.current);
    };
  }, [cacheKey]);

  useEffect(() => {
    if (summary && state.status === "waiting") {
      clearTimeout(timer.current);
      inFlight.current = false;
      setState({ status: "idle", error: "" });
    }
  }, [summary, state.status]);

  const ask = useCallback(() => {
    if (!docId || !request || uid === "") return;
    if (inFlight.current) return;
    inFlight.current = true;
    const id = docId;
    setState({ status: "sending", error: "" });
    sent(api.post(id, requestDoc(request, uid, Date.now())), sendMs).then(
      () => {
        setState({ status: "waiting", error: "" });
        timer.current = setTimeout(() => {
          api.remove(id).catch(() => undefined);
          inFlight.current = false;
          setState({ status: "unavailable", error: "" });
        }, waitMs);
      },
      (error: unknown) => {
        api.remove(id).catch(() => undefined);
        inFlight.current = false;
        setState({
          status: "failed",
          error: error instanceof Error ? error.message : "Unknown error.",
        });
      },
    );
  }, [api, docId, request, uid, sendMs, waitMs]);

  return {
    summary,
    status: state.status,
    error: state.error,
    ready: docId !== null,
    ask,
  };
}
