import { useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { enqueueWrite } from "../outbox/outbox";
import type { Column, Table } from "./assignments";
import { type Kind, tablePath, toDoc, withColumns } from "./edit";

const labels = {
  assignments: "T-REx assignments",
  teamList: "T-REx team list",
} as const;

const signedOut = "Sign in again to save changes.";

const stamp = (t: Table) => Date.parse(t.updatedAt) || 0;

export function useTableEdits(base: { assignments: Table; teamList: Table }) {
  const auth = useAuth();
  const [local, setLocal] = useState<Partial<Record<Kind, Table>>>({});
  const [error, setError] = useState("");

  const current = (kind: Kind): Table => {
    const mine = local[kind];
    return mine && stamp(mine) >= stamp(base[kind]) ? mine : base[kind];
  };

  const canSave = auth.status === "signed-in" && auth.uid !== null;

  async function write(kind: Kind, next: Table) {
    setLocal((l) => ({ ...l, [kind]: next }));
    setError("");
    try {
      await enqueueWrite(tablePath[kind], toDoc(kind, next), labels[kind]);
    } catch (e) {
      setLocal((l) => ({ ...l, [kind]: undefined }));
      setError(e instanceof Error ? e.message : "Could not save the change.");
    }
  }

  const stamped = (kind: Kind, columns: Column[]) =>
    auth.uid === null
      ? null
      : withColumns(
          current(kind),
          columns,
          { uid: auth.uid, displayName: auth.displayName ?? "" },
          new Date(),
        );

  async function save(kind: Kind, change: (c: Column[]) => Column[]) {
    const next = stamped(kind, change(current(kind).columns));
    if (next) await write(kind, next);
    else setError(signedOut);
  }

  async function setTitle(title: string) {
    const next = stamped("teamList", current("teamList").columns);
    if (next) await write("teamList", { ...next, title });
    else setError(signedOut);
  }

  return {
    assignments: current("assignments"),
    teamList: current("teamList"),
    canSave,
    error,
    save,
    setTitle,
  };
}
