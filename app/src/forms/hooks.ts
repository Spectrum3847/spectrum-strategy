import { useEffect, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import type { Feed } from "../data/store";

const settleMs = 4000;

export function useSettled(feed: Feed<unknown>): boolean {
  const { status } = useAuth();
  const [late, setLate] = useState(false);
  // biome-ignore lint/correctness/useExhaustiveDependencies: status restarts the wait
  useEffect(() => {
    setLate(false);
    const timer = setTimeout(() => setLate(true), settleMs);
    return () => clearTimeout(timer);
  }, [status]);
  return feed.ready || late || status === "signed-out";
}

export function useIsLead(): boolean {
  const roles = useRoles();
  return roles.status === "ready" && isLead(roles.roles);
}
