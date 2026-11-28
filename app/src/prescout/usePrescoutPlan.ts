import { useEffect, useState } from "react";
import { readCache, writeCache } from "../data/cache";
import { teamKey } from "../data/tbaKey";
import { useOnline } from "../ui/useOnline";
import { type PrescoutPlan, planMatches, tbaSource } from "./finder";

export interface PlanState {
  status: "none" | "loading" | "ready" | "failed";
  plan: PrescoutPlan | null;
  saved: boolean;
}

const cacheKey = (event: string, team: number) =>
  `ss.prescout.plan.${event}.${team}`;

const yearOf = (eventKey: string) => {
  const year = Number(eventKey.slice(0, 4));
  return Number.isInteger(year) && year > 0 ? year : null;
};

export function usePrescoutPlan(team: number, eventKey: string): PlanState {
  const online = useOnline();
  const year = yearOf(eventKey);
  const [state, setState] = useState<PlanState>(() => ({
    status: year === null ? "none" : "loading",
    plan:
      year === null ? null : readCache<PrescoutPlan>(cacheKey(eventKey, team)),
    saved: false,
  }));

  useEffect(() => {
    if (year === null || !online) return;
    let live = true;
    (async () => {
      try {
        const apiKey = await teamKey();
        if (!apiKey) throw new Error("No TBA key available");
        const plan = await planMatches(
          team,
          year,
          eventKey,
          tbaSource(team, year, apiKey),
        );
        writeCache(cacheKey(eventKey, team), plan);
        if (live) setState({ status: "ready", plan, saved: false });
      } catch (error) {
        console.warn("Prescout match lookup failed", error);
        if (live) {
          setState((s) =>
            s.plan
              ? { status: "ready", plan: s.plan, saved: true }
              : { status: "failed", plan: null, saved: false },
          );
        }
      }
    })();
    return () => {
      live = false;
    };
  }, [team, eventKey, year, online]);

  if (year !== null && !online && state.status === "loading") {
    return state.plan
      ? { status: "ready", plan: state.plan, saved: true }
      : { status: "failed", plan: null, saved: false };
  }
  return state;
}
