import type { DocumentData } from "firebase/firestore";
import { useEffect, useMemo, useSyncExternalStore } from "react";
import { useAuth } from "../auth/AuthProvider";
import { useRoles } from "../auth/rolesContext";
import { dismissItem, enqueueWrite, getOutbox } from "../outbox/outbox";
import { useOutbox } from "../outbox/useOutbox";
import { useOnline } from "../ui/useOnline";
import { BoardController } from "./controller";
import type { Robot } from "./edit";
import { bundled } from "./field";
import { boardKey, loadLocal, saveLocal } from "./local";
import { useRemoteBoard, useRemoteBoardById } from "./remote";
import { type DeliveryState, deliveryState } from "./sync";

const debounceMs = 1000;
const waitMs = 3000;

const pathOf = (id: string) => `strategyBoards/${id}`;

export interface Args {
  eventKey: string;
  matchNumber: number;
  alliance: "Red" | "Blue";
  robots: Robot[];
  label: string;
  id?: string;
  localKey?: string;
  practice?: boolean;
}

export function useBoard(args: Args) {
  const auth = useAuth();
  const roles = useRoles();
  const online = useOnline();
  const outbox = useOutbox();
  const byMatch = useRemoteBoard(
    args.id ? "" : args.eventKey,
    args.matchNumber,
  );
  const byId = useRemoteBoardById(args.id ?? "");
  const remote = args.id ? byId : byMatch;

  const key = args.localKey ?? boardKey(args.eventKey, args.matchNumber);
  const teams = args.robots.map((r) => `${r.side}${r.team}`).join(",");
  // biome-ignore lint/correctness/useExhaustiveDependencies: the key and roster are the trigger
  const controller = useMemo(() => {
    const unconfirmed = (id: string) =>
      getOutbox().filter(
        (i) => i.path === pathOf(id) && i.status !== "in-database",
      );
    const controller = new BoardController(
      {
        load: () => loadLocal(key),
        save: (record) => saveLocal(key, record),
        enqueue: (doc) =>
          enqueueWrite(pathOf(String(doc.id)), doc as DocumentData, args.label),
        unsent: (id) => unconfirmed(id).length > 0,
        discard: (id) => {
          for (const i of unconfirmed(id)) dismissItem(i.id);
        },
        now: Date.now,
        newId: () => args.id ?? crypto.randomUUID(),
        debounceMs,
      },
      {
        eventKey: args.eventKey,
        matchNumber: args.matchNumber,
        alliance: args.alliance,
        robots: args.robots,
        fieldId: bundled.latest,
      },
    );
    return controller;
  }, [key, teams]);

  useEffect(() => {
    void controller.start();
    const timer = setTimeout(() => controller.proceed(), waitMs);
    const leave = () => controller.flush();
    const hidden = () => {
      if (document.visibilityState === "hidden") controller.flush();
    };
    window.addEventListener("pagehide", leave);
    document.addEventListener("visibilitychange", hidden);
    return () => {
      clearTimeout(timer);
      window.removeEventListener("pagehide", leave);
      document.removeEventListener("visibilitychange", hidden);
      controller.dispose();
    };
  }, [controller]);

  const practice = args.practice === true;
  useEffect(() => {
    controller.setPractice(practice);
  }, [controller, practice]);

  const uid = auth.uid ?? "";
  const displayName =
    (roles.status === "ready" ? roles.displayName : "") ||
    auth.displayName ||
    "";
  useEffect(() => {
    controller.setAuthor({ uid, displayName });
  }, [controller, uid, displayName]);

  const settled =
    remote.ready &&
    (remote.board !== null || !remote.fromCache || !online || remote.failed);
  useEffect(() => {
    controller.setRemote(remote.board, settled, remote.fromCache);
  }, [controller, remote.board, remote.fromCache, settled]);

  const state = useSyncExternalStore(
    controller.subscribe,
    controller.getSnapshot,
  );
  const item = outbox.find((i) => i.path === pathOf(state.session.id));
  const delivery: DeliveryState = deliveryState({
    hasBoard: state.hasBoard,
    local: state.local,
    handed: state.handed,
    signedIn: auth.status === "signed-in" && uid !== "",
    item: item
      ? { status: item.status, ...(item.error ? { error: item.error } : {}) }
      : undefined,
    remote: state.remote,
  });

  return { controller, state, delivery, online, failed: remote.failed };
}
