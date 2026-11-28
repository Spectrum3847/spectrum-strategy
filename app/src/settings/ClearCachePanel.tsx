import { useState } from "react";
import { useOnline } from "../ui/useOnline";
import { browserCacheEnv, clearAppCache } from "./clearCache";

export function ClearCachePanel() {
  const online = useOnline();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const clear = async () => {
    setBusy(true);
    setError(null);
    try {
      await clearAppCache(browserCacheEnv());
      window.location.reload();
    } catch (e) {
      setBusy(false);
      setError(e instanceof Error ? e.message : "Could not clear the cache.");
    }
  };

  return (
    <section className="panel" aria-labelledby="cache-h">
      <h2 id="cache-h">App cache</h2>
      <p className="secondary">
        The app keeps itself on this device so it opens offline, which can show
        an old version after an update. Clear it to download the current one.
        Entries that are not sent yet stay on this device.
      </p>
      {!online && (
        <p className="secondary">
          Needs a connection: the app downloads again after it clears.
        </p>
      )}
      {error && (
        <p className="notice" role="alert">
          {error}
        </p>
      )}
      <div className="actions">
        <button
          type="button"
          className="btn"
          disabled={busy || !online}
          onClick={clear}
        >
          {busy ? "Clearing" : "Clear cache and reload"}
        </button>
      </div>
    </section>
  );
}
