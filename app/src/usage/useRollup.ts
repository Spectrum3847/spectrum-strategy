import { doc, getDoc } from "firebase/firestore";
import { useCallback, useEffect, useState } from "react";
import { db } from "../firebase/client";
import { parseRollup, type UsageRollup } from "./rollup";

export type RollupState =
  | { status: "loading" }
  | { status: "ready"; rollup: UsageRollup }
  | { status: "error"; message: string };

export const rollupMissing =
  "No usage rollup yet. The daily job writes it; if this persists, check the Usage rollup cron workflow.";
export const rollupDenied = "Usage data is limited to the developer role.";

export type RollupReader = () => Promise<Record<string, unknown> | null>;

const readFirestore: RollupReader = async () => {
  const snap = await getDoc(doc(db, "telemetryRollup", "current"));
  return snap.exists() ? snap.data() : null;
};

export async function loadRollup(read: RollupReader): Promise<RollupState> {
  try {
    const data = await read();
    if (!data) return { status: "error", message: rollupMissing };
    return { status: "ready", rollup: parseRollup(data) };
  } catch (error) {
    const code = (error as { code?: string }).code;
    return {
      status: "error",
      message:
        code === "permission-denied"
          ? rollupDenied
          : "Could not read usage data. Check your connection and try again.",
    };
  }
}

export function useRollup(read: RollupReader = readFirestore) {
  const [state, setState] = useState<RollupState>({ status: "loading" });
  const load = useCallback(() => {
    setState({ status: "loading" });
    void loadRollup(read).then(setState);
  }, [read]);
  useEffect(load, [load]);
  return { state, reload: load };
}
