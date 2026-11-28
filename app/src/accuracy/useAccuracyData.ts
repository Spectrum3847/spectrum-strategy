import { doc, onSnapshot } from "firebase/firestore";
import { useCallback, useEffect, useState } from "react";
import { readCache, writeCache } from "../data/cache";
import { type AllianceFuel, fetchAllianceCounts } from "../data/tbaBreakdown";
import { teamKey } from "../data/tbaKey";
import { db } from "../firebase/client";
import { enqueueWrite } from "../outbox/outbox";
import { type MappingDoc, mappingPath, readMapping } from "./mapping";
import { season } from "./season";

export type OfficialStatus = "none" | "loading" | "ready" | "failed";
export type OfficialProblem =
  | "no-key"
  | "rejected"
  | "not-found"
  | "unreachable";

interface Stored {
  fetchedAt: string;
  alliances: AllianceFuel[];
}

const cacheKey = (event: string) => `ss.tba.official.${event}`;

export interface Official {
  status: OfficialStatus;
  alliances: AllianceFuel[];
  fetchedAt: string | null;
  problem: OfficialProblem | null;
  refresh(): void;
}

function problemOf(error: unknown): OfficialProblem {
  const text = error instanceof Error ? error.message : "";
  if (/\b40[13]\b/.test(text)) return "rejected";
  if (/\b404\b/.test(text)) return "not-found";
  return "unreachable";
}

export function useOfficialCounts(
  eventKey: string,
  enabled: boolean,
): Official {
  const [state, setState] = useState<Omit<Official, "refresh">>({
    status: "none",
    alliances: [],
    fetchedAt: null,
    problem: null,
  });

  const load = useCallback(async () => {
    if (eventKey === "") return;
    setState((s) => ({ ...s, status: "loading", problem: null }));
    try {
      const apiKey = await teamKey();
      if (!apiKey) {
        setState((s) => ({ ...s, status: "failed", problem: "no-key" }));
        return;
      }
      const alliances = await fetchAllianceCounts(
        eventKey,
        apiKey,
        season.breakdownPath,
      );
      const fetchedAt = new Date().toISOString();
      const stored: Stored = { fetchedAt, alliances };
      writeCache(cacheKey(eventKey), stored);
      setState({ status: "ready", alliances, fetchedAt, problem: null });
    } catch (error) {
      console.warn("Official counts refresh failed", error);
      setState((s) => ({ ...s, status: "failed", problem: problemOf(error) }));
    }
  }, [eventKey]);

  useEffect(() => {
    if (!enabled || eventKey === "") return;
    const cached = readCache<Stored>(cacheKey(eventKey));
    setState({
      status: cached ? "ready" : "none",
      alliances: cached?.alliances ?? [],
      fetchedAt: cached?.fetchedAt ?? null,
      problem: null,
    });
    void load();
    const again = () => void load();
    window.addEventListener("online", again);
    return () => window.removeEventListener("online", again);
  }, [enabled, eventKey, load]);

  return { ...state, refresh: () => void load() };
}

export type MappingStatus = "loading" | "ready" | "failed";

export function useAccuracyMapping(enabled: boolean): {
  status: MappingStatus;
  mapping: MappingDoc | null;
} {
  const [state, setState] = useState<{
    status: MappingStatus;
    mapping: MappingDoc | null;
  }>({ status: "loading", mapping: null });
  useEffect(() => {
    if (!enabled) return;
    return onSnapshot(
      doc(db, mappingPath),
      (snap) =>
        setState({ status: "ready", mapping: readMapping(snap.data()) }),
      (error) => {
        console.warn("Could not read the accuracy mapping", error);
        setState((s) => ({ ...s, status: "failed" }));
      },
    );
  }, [enabled]);
  return state;
}

export const saveMapping = (mapping: MappingDoc) =>
  enqueueWrite(mappingPath, mapping, "Accuracy mapping");
