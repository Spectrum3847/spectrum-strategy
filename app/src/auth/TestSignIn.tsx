import { signInWithCustomToken } from "firebase/auth";
import { useState } from "react";
import accounts from "../../e2e/accounts.json";
import { dataAuth } from "../firebase/client";

const b64 = (value: object) =>
  btoa(JSON.stringify(value))
    .replace(/=+$/, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

function unsignedToken(uid: string): string {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss: "firebase-auth-emulator@example.com",
    sub: "firebase-auth-emulator@example.com",
    aud: "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit",
    iat: now,
    exp: now + 3600,
    uid,
  };
  return `${b64({ alg: "none", typ: "JWT" })}.${b64(claims)}.`;
}

export default function TestSignIn() {
  const [uid, setUid] = useState(accounts[0]?.uid ?? "");
  const [error, setError] = useState<string | null>(null);
  return (
    <section className="panel" aria-labelledby="test-signin-h">
      <h2 id="test-signin-h">Test sign-in</h2>
      <p className="secondary">
        This build talks to the local emulators, not the team's database.
      </p>
      <label>
        Test account
        <select
          className="input"
          value={uid}
          onChange={(e) => setUid(e.target.value)}
        >
          {accounts.map((a) => (
            <option key={a.uid} value={a.uid}>
              {a.name} ({a.roles.join(", ")})
            </option>
          ))}
        </select>
      </label>
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      <div className="actions">
        <button
          type="button"
          className="btn"
          onClick={() => {
            setError(null);
            signInWithCustomToken(dataAuth, unsignedToken(uid)).catch(
              (e: unknown) =>
                setError(e instanceof Error ? e.message : String(e)),
            );
          }}
        >
          Test sign-in
        </button>
      </div>
    </section>
  );
}
