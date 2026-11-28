import { doc, onSnapshot } from "firebase/firestore";
import { useMemo } from "react";
import { useAuth } from "../auth/AuthProvider";
import { createStore, storeFor, useStore } from "../data/store";
import { db } from "../firebase/client";
import { parseAssignments, parseTeamList, type Table } from "./assignments";

interface DocState {
  ready: boolean;
  failed: boolean;
  missing: boolean;
  data: Record<string, unknown> | null;
}

const idle: DocState = {
  ready: false,
  failed: false,
  missing: false,
  data: null,
};

function docStore(path: string) {
  return createStore<DocState>(idle, (set, get) =>
    onSnapshot(
      doc(db, path),
      (snap) =>
        set({
          ready: true,
          failed: false,
          missing: !snap.exists(),
          data: snap.exists() ? snap.data() : null,
        }),
      (error) => {
        console.warn(`Could not read ${path}`, error);
        set({ ...get(), ready: true, failed: true });
      },
    ),
  );
}

export interface TrexTables {
  assignments: Table;
  teamList: Table;
  ready: boolean;
  failed: boolean;
  missing: boolean;
}

export function useTrexTables(): TrexTables {
  const signedIn = useAuth().status === "signed-in";
  const path = {
    assignments: "appConfig/trexAssignments",
    teamList: "appConfig/trexTeamList",
  };
  const a = useStore(
    signedIn
      ? storeFor(`doc:${path.assignments}`, () => docStore(path.assignments))
      : null,
    idle,
  );
  const t = useStore(
    signedIn
      ? storeFor(`doc:${path.teamList}`, () => docStore(path.teamList))
      : null,
    idle,
  );
  const assignments = useMemo(() => parseAssignments(a.data), [a.data]);
  const teamList = useMemo(() => parseTeamList(t.data), [t.data]);
  return {
    assignments,
    teamList,
    ready: a.ready && t.ready,
    failed: a.failed || t.failed,
    missing: a.missing && t.missing,
  };
}
