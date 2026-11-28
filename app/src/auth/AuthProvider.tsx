import { onAuthStateChanged } from "firebase/auth";
import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import { centralAuth, dataAuth } from "../firebase/client";
import { firebaseDeps } from "./firebaseDeps";
import { classifyHandshakeError, signInThroughCentral } from "./handshake";

export interface AuthState {
  status: "loading" | "signed-out" | "signing-in" | "signed-in";
  uid: string | null;
  displayName: string | null;
  email: string | null;
  error: string | null;
  signIn(): Promise<void>;
  signOut(): Promise<void>;
}

const AuthContext = createContext<AuthState | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [status, setStatus] = useState<AuthState["status"]>("loading");
  const [uid, setUid] = useState<string | null>(null);
  const [displayName, setDisplayName] = useState<string | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(
    () =>
      onAuthStateChanged(dataAuth, (user) => {
        setUid(user?.uid ?? null);
        setDisplayName(user?.displayName ?? null);
        setEmail(user?.email ?? null);
        setStatus(user ? "signed-in" : "signed-out");
      }),
    [],
  );

  const signIn = useCallback(async () => {
    setError(null);
    setStatus("signing-in");
    try {
      await signInThroughCentral(firebaseDeps);
    } catch (e) {
      setError(classifyHandshakeError(e).message);
      setStatus("signed-out");
    }
  }, []);

  const signOut = useCallback(async () => {
    await Promise.allSettled([dataAuth.signOut(), centralAuth.signOut()]);
  }, []);

  const value = useMemo(
    () => ({ status, uid, displayName, email, error, signIn, signOut }),
    [status, uid, displayName, email, error, signIn, signOut],
  );
  return <AuthContext value={value}>{children}</AuthContext>;
}

export function useAuth(): AuthState {
  const value = useContext(AuthContext);
  if (!value) throw new Error("useAuth needs an AuthProvider");
  return value;
}
