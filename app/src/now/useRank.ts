import { useEffect, useState } from "react";
import { tbaKeyCache } from "../scout/local";
import { fetchRankings, parseRank, type TeamRank } from "./rankings";

export type RankStatus = "none" | "loading" | "ready" | "failed";

export interface RankState {
  rank: TeamRank | null;
  fetchedAt: string | null;
  status: RankStatus;
}

interface Cached {
  fetchedAt: string;
  rank: TeamRank | null;
}

const cacheKey = (event: string, team: number) => `ss.rank.${event}.${team}`;

function readCache(event: string, team: number): Cached | null {
  try {
    const raw = localStorage.getItem(cacheKey(event, team));
    return raw === null ? null : (JSON.parse(raw) as Cached);
  } catch {
    return null;
  }
}

function writeCache(event: string, team: number, value: Cached) {
  try {
    localStorage.setItem(cacheKey(event, team), JSON.stringify(value));
  } catch {
  }
}

const refreshMs = 2 * 60_000;

export function useRank(
  eventKey: string,
  team: number | null,
  after: string | null,
): RankState {
  const [state, setState] = useState<RankState>({
    rank: null,
    fetchedAt: null,
    status: "none",
  });

  // biome-ignore lint/correctness/useExhaustiveDependencies: after reruns the fetch
  useEffect(() => {
    if (eventKey === "" || team === null) {
      setState({ rank: null, fetchedAt: null, status: "none" });
      return;
    }
    const cached = readCache(eventKey, team);
    setState({
      rank: cached?.rank ?? null,
      fetchedAt: cached?.fetchedAt ?? null,
      status: cached ? "ready" : "none",
    });
    let live = true;
    const load = async () => {
      const apiKey = tbaKeyCache.get();
      if (!apiKey) return;
      setState((s) => (s.status === "ready" ? s : { ...s, status: "loading" }));
      try {
        const rank = parseRank(await fetchRankings(eventKey, apiKey), team);
        const fetchedAt = new Date().toISOString();
        writeCache(eventKey, team, { fetchedAt, rank });
        if (live) setState({ rank, fetchedAt, status: "ready" });
      } catch {
        if (live) {
          setState((s) =>
            s.status === "ready" ? s : { ...s, status: "failed" },
          );
        }
      }
    };
    void load();
    const again = () => void load();
    window.addEventListener("online", again);
    const timer = setInterval(again, refreshMs);
    return () => {
      live = false;
      window.removeEventListener("online", again);
      clearInterval(timer);
    };
  }, [eventKey, team, after]);

  return state;
}
