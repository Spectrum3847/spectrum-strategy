import { useId } from "react";
import { sharingStore, useSharing } from "./prefs";
import "./usage.css";

export function SharePanel() {
  const sharing = useSharing();
  const id = useId();
  return (
    <section className="panel" aria-labelledby={`${id}-h`}>
      <h2 id={`${id}-h`}>Usage data</h2>
      <p className="secondary">
        Share which screens get opened, with the app version and platform, to
        help improve the app. No names, accounts or entries are sent.
      </p>
      <label className="share-switch">
        <input
          type="checkbox"
          checked={sharing}
          onChange={(e) => sharingStore.set(e.target.checked)}
        />
        <span>Share anonymous usage data</span>
      </label>
    </section>
  );
}
