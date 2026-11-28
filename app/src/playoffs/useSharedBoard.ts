import { useCallback, useEffect, useRef, useState } from "react";
import { useAuth } from "../auth/AuthProvider";
import { useRoles } from "../auth/rolesContext";
import { useOutbox } from "../outbox/useOutbox";
import { useOnline } from "../ui/useOnline";
import type { PlayoffBoard } from "./board";
import { sendBoard, useRemoteBoard } from "./remote";
import {
  boardPath,
  isBlank,
  nextStamp,
  sameBoard,
  takesRemote,
} from "./shared";
import {
  blankCache,
  type Cached,
  clearLegacy,
  loadCache,
  loadLegacy,
  saveCache,
} from "./storage";

const debounceMs = 800;

export function useSharedBoard(eventKey: string, canWrite: boolean) {
  const auth = useAuth();
  const roles = useRoles();
  const online = useOnline();
  const outbox = useOutbox();
  const remote = useRemoteBoard(eventKey);

  const signedIn = auth.status === "signed-in";
  const by =
    (roles.status === "ready" ? roles.displayName : "") ||
    auth.displayName ||
    "";

  const [state, setState] = useState<Cached>(
    () => loadCache(eventKey) ?? blankCache(),
  );
  const latest = useRef(state);
  const seenMs = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const [kept, setKept] = useState(true);
  const [queueFailed, setQueueFailed] = useState(false);
  const [legacy, setLegacy] = useState(() => loadLegacy(eventKey));

  const item = outbox.find((i) => i.path === boardPath(eventKey));
  const unsent = item?.status === "on-device" || item?.status === "sending";

  const flush = useCallback(() => {
    clearTimeout(timer.current);
    const cur = latest.current;
    if (!cur.pending || !canWrite || !signedIn) return;
    const ms = nextStamp(cur.ms, seenMs.current);
    const sent: Cached = { ...cur, ms, pending: false };
    sendBoard(eventKey, cur.board, ms, cur.by).then(
      () => {
        setQueueFailed(false);
        if (latest.current !== cur) return;
        latest.current = sent;
        setState(sent);
        saveCache(eventKey, sent);
      },
      () => setQueueFailed(true),
    );
  }, [eventKey, canWrite, signedIn]);

  useEffect(() => {
    flush();
    const hidden = () => {
      if (document.visibilityState === "hidden") flush();
    };
    window.addEventListener("pagehide", flush);
    document.addEventListener("visibilitychange", hidden);
    return () => {
      window.removeEventListener("pagehide", flush);
      document.removeEventListener("visibilitychange", hidden);
      flush();
    };
  }, [flush]);

  const shared = remote.shared;
  useEffect(() => {
    if (!shared) return;
    seenMs.current = Math.max(seenMs.current, shared.ms);
    const cur = latest.current;
    if (
      !takesRemote({
        heldMs: cur.ms,
        remoteMs: shared.ms,
        unsent: cur.pending || unsent,
      })
    ) {
      return;
    }
    const next: Cached = {
      board: shared.board,
      ms: shared.ms,
      by: shared.by,
      pending: false,
    };
    latest.current = next;
    setState(next);
    setKept(saveCache(eventKey, next));
  }, [shared, unsent, eventKey]);

  const change = useCallback(
    (fn: (b: PlayoffBoard) => PlayoffBoard) => {
      if (!canWrite) return;
      const cur = latest.current;
      const board = fn(cur.board);
      if (board === cur.board) return;
      const next: Cached = {
        board,
        ms: nextStamp(Date.now(), cur.ms, seenMs.current),
        by,
        pending: true,
      };
      latest.current = next;
      setState(next);
      setKept(saveCache(eventKey, next));
      clearTimeout(timer.current);
      timer.current = setTimeout(flush, debounceMs);
    },
    [canWrite, by, eventKey, flush],
  );

  const settled =
    remote.ready &&
    (shared !== null || !remote.fromCache || !online || remote.failed);
  const adopted = state.ms >= (shared?.ms ?? 0);
  const waiting =
    canWrite &&
    legacy !== null &&
    settled &&
    !remote.failed &&
    adopted &&
    !state.pending;
  const offer =
    waiting &&
    legacy !== null &&
    !isBlank(legacy) &&
    !sameBoard(legacy, state.board)
      ? legacy
      : null;

  useEffect(() => {
    if (waiting && offer === null) {
      clearLegacy(eventKey);
      setLegacy(null);
    }
  }, [waiting, offer, eventKey]);

  const upload = () => {
    if (!offer) return;
    change(() => offer);
    clearLegacy(eventKey);
    setLegacy(null);
  };
  const discard = () => {
    clearLegacy(eventKey);
    setLegacy(null);
  };

  return {
    board: state.board,
    ms: state.ms,
    by: state.by,
    change,
    kept,
    queueFailed,
    failed: remote.failed,
    item,
    signedIn,
    online,
    offer,
    upload,
    discard,
  };
}
