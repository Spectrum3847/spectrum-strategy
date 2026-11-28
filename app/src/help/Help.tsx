import { lazy, Suspense, useEffect, useMemo, useState } from "react";
import { Link, useLocation, useParams } from "react-router";
import { useRoles } from "../auth/rolesContext";
import { bundledIds, docsFor, loadDoc } from "./docs";
import "./help.css";

const Markdown = lazy(() =>
  import("./Markdown").then((m) => ({ default: m.Markdown })),
);

function Chevron() {
  return (
    <svg
      viewBox="0 0 24 24"
      width="20"
      height="20"
      aria-hidden="true"
      focusable="false"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M9 6l6 6-6 6" />
    </svg>
  );
}

function useDocs() {
  const roles = useRoles();
  const list = roles.status === "ready" ? roles.roles : [];
  const bundled = useMemo(bundledIds, []);
  return { bundled, docs: docsFor(list, bundled) };
}

export function Help() {
  const { docs } = useDocs();
  return (
    <div className="help">
      <h1>Help</h1>
      {docs.length === 0 ? (
        <p className="secondary">This build has no manuals.</p>
      ) : (
        <ul className="plain help-list">
          {docs.map((doc) => (
            <li key={doc.id}>
              <Link to={`/help/${doc.id}`}>
                <span className="help-item-text">
                  <span className="help-item-title">{doc.title}</span>
                  <span className="secondary">{doc.detail}</span>
                </span>
                <Chevron />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

type Loaded =
  | { id: string; try: number; status: "ready"; text: string }
  | { id: string; try: number; status: "failed" };

export function HelpDoc() {
  const { doc: id = "" } = useParams();
  const { hash } = useLocation();
  const { bundled, docs } = useDocs();
  const doc = docs.find((d) => d.id === id);
  const [attempt, setAttempt] = useState(0);
  const [loaded, setLoaded] = useState<Loaded | null>(null);

  useEffect(() => {
    if (!doc) return;
    let live = true;
    loadDoc(doc.id).then(
      (text) =>
        live && setLoaded({ id: doc.id, try: attempt, status: "ready", text }),
      () => live && setLoaded({ id: doc.id, try: attempt, status: "failed" }),
    );
    return () => {
      live = false;
    };
  }, [doc, attempt]);

  const current = loaded?.id === id && loaded.try === attempt ? loaded : null;
  const ready = current?.status === "ready";

  useEffect(() => {
    if (!ready) return;
    const target = hash
      ? document.getElementById(decodeURIComponent(hash.slice(1)))
      : null;
    if (target) target.scrollIntoView();
    else window.scrollTo(0, 0);
  }, [ready, hash]);

  return (
    <div className="help">
      <Link className="help-back" to="/help">
        <span className="help-back-icon">
          <Chevron />
        </span>
        Help
      </Link>
      {!doc ? (
        <>
          <h1>Manual not found</h1>
          <p className="secondary">
            This manual is not available in this build or for your role.
          </p>
        </>
      ) : current?.status === "failed" ? (
        <>
          <h1>{doc.title}</h1>
          <p className="notice" role="alert">
            The manual could not be loaded.
          </p>
          <div className="actions">
            <button
              type="button"
              className="btn"
              onClick={() => setAttempt((n) => n + 1)}
            >
              Try again
            </button>
          </div>
        </>
      ) : current?.status === "ready" ? (
        <Suspense fallback={<p className="secondary">Loading.</p>}>
          <Markdown source={current.text} bundled={bundled} />
        </Suspense>
      ) : (
        <p className="secondary" role="status">
          Loading.
        </p>
      )}
    </div>
  );
}
