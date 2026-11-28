import { lazy, type ReactNode, Suspense } from "react";
import { Link } from "react-router";
import { useAuth } from "../auth/AuthProvider";
import { useRoles } from "../auth/rolesContext";
import "./ui.css";

const TestSignIn =
  import.meta.env.VITE_FIREBASE_EMULATORS === "true"
    ? lazy(() => import("../auth/TestSignIn"))
    : null;

function StatusScreen({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <main className="status-screen">
      <div className="status-inner">
        <h1>{title}</h1>
        {children}
      </div>
    </main>
  );
}

export function LoadingScreen() {
  return (
    <StatusScreen title="Loading your access">
      <p className="secondary" role="status">
        Checking which parts of the app your account can open.
      </p>
    </StatusScreen>
  );
}

export function SignedOutScreen() {
  const auth = useAuth();
  return (
    <StatusScreen title="You are signed out">
      <p>Sign in with the Google account you use for the team.</p>
      {auth.error && (
        <p className="notice" role="alert">
          {auth.error}
        </p>
      )}
      <div className="actions">
        <button type="button" className="btn primary" onClick={auth.signIn}>
          Sign in with Google
        </button>
      </div>
      {TestSignIn && (
        <Suspense fallback={null}>
          <TestSignIn />
        </Suspense>
      )}
    </StatusScreen>
  );
}

export function NoAccessScreen() {
  const auth = useAuth();
  const name = auth.displayName;
  return (
    <StatusScreen title="No access">
      <p>
        {name ? `You are signed in as ${name}. ` : ""}This account has no role
        that opens the app, so it has no access. Ask an admin to give it a role.
      </p>
      <div className="actions">
        <button type="button" className="btn" onClick={auth.signOut}>
          Switch account
        </button>
      </div>
    </StatusScreen>
  );
}

export function RolesUnavailableScreen() {
  const auth = useAuth();
  const roles = useRoles();
  return (
    <StatusScreen title="Your access could not be checked">
      <p>
        This device has not loaded your roles yet. Connect to the internet once,
        then try again. After that your roles are kept for offline use.
      </p>
      <div className="actions">
        <button type="button" className="btn primary" onClick={roles.retry}>
          Try again
        </button>
        <button type="button" className="btn" onClick={auth.signOut}>
          Switch account
        </button>
      </div>
    </StatusScreen>
  );
}

export function NotAvailable({
  who = "strategy, admin and developer accounts",
}: {
  who?: string;
}) {
  return (
    <>
      <h1>Not available for your role</h1>
      <p>
        Your account can open Now, Scout and Settings. This page is for {who}.
      </p>
      <div className="actions">
        <Link className="btn" to="/">
          Back to Now
        </Link>
      </div>
    </>
  );
}
