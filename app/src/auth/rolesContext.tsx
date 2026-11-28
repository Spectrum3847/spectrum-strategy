import { doc, onSnapshot, setDoc } from "firebase/firestore";
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { db } from "../firebase/client";
import { useOnline } from "../ui/useOnline";
import { useAuth } from "./AuthProvider";
import {
  newProfileDoc,
  type ProfileRead,
  type RolesState,
  readProfile,
  rolesState,
} from "./roles";

export type RolesContext = RolesState & { retry(): void };

const Ctx = createContext<RolesContext | null>(null);

const stallMs = 8000;

export function RolesProvider({ children }: { children: ReactNode }) {
  const auth = useAuth();
  const online = useOnline();
  const uid = auth.status === "signed-in" ? auth.uid : null;
  const [attempt, setAttempt] = useState(0);
  const [read, setRead] = useState<{ uid: string; read: ProfileRead } | null>(
    null,
  );
  const [stalledFor, setStalledFor] = useState<string | null>(null);
  const [canonical, setCanonical] = useState<{
    uid: string;
    name: string;
  } | null>(null);

  // biome-ignore lint/correctness/useExhaustiveDependencies: attempt restarts the listener
  useEffect(() => {
    setRead(null);
    setStalledFor(null);
    if (!uid) return;
    const timer = setTimeout(() => setStalledFor(uid), stallMs);
    const stop = onSnapshot(
      doc(db, "userProfiles", uid),
      { includeMetadataChanges: true },
      (snap) => {
        const result = readProfile(uid, {
          exists: snap.exists(),
          fromCache: snap.metadata.fromCache,
          data: snap.data(),
        });
        if (result.kind !== "unknown") clearTimeout(timer);
        setRead({ uid, read: result });
      },
      () => {
        clearTimeout(timer);
        setRead({ uid, read: { kind: "error" } });
      },
    );
    return () => {
      clearTimeout(timer);
      stop();
    };
  }, [uid, attempt]);

  const current = read?.uid === uid ? read.read : null;

  const created = useRef<string | null>(null);
  useEffect(() => {
    if (!uid || current?.kind !== "missing" || created.current === uid) return;
    created.current = uid;
    setDoc(
      doc(db, "userProfiles", uid),
      newProfileDoc(uid, auth.displayName ?? "", auth.email, new Date()),
    ).catch(() => {
      created.current = null;
    });
  }, [uid, current, auth.displayName, auth.email]);
  const canonicalUid =
    current?.kind === "profile" ? current.profile.canonicalUid : null;

  useEffect(() => {
    if (!canonicalUid) return;
    return onSnapshot(
      doc(db, "userProfiles", canonicalUid),
      (snap) => {
        const name = snap.data()?.displayName;
        setCanonical(
          typeof name === "string" && name !== ""
            ? { uid: canonicalUid, name }
            : null,
        );
      },
      () => setCanonical(null),
    );
  }, [canonicalUid]);

  const retry = useCallback(() => setAttempt((n) => n + 1), []);

  const state = rolesState({
    auth: auth.status,
    uid,
    authName: auth.displayName,
    read: current,
    canonicalName:
      canonicalUid !== null && canonical?.uid === canonicalUid
        ? canonical.name
        : null,
    stalled: uid !== null && stalledFor === uid,
    online,
  });
  const value = useMemo(() => ({ ...state, retry }), [state, retry]);
  return <Ctx value={value}>{children}</Ctx>;
}

export function useRoles(): RolesContext {
  const value = useContext(Ctx);
  if (!value) throw new Error("useRoles needs a RolesProvider");
  return value;
}
