import { useState } from "react";
import {
  currentDevice,
  readDismissed,
  showInstallPrompt,
  writeDismissed,
} from "./installPrompt";
import "./install.css";

export function InstallBanner() {
  const [shown, setShown] = useState(() =>
    showInstallPrompt(currentDevice(), readDismissed(), Date.now()),
  );
  if (!shown) return null;
  return (
    <section className="install" aria-labelledby="install-h">
      <h2 id="install-h">Add this app to your Home Screen</h2>
      <p>
        Unsent entries are safer there, and shift reminders only work from the
        Home Screen app.
      </p>
      <ol>
        <li>Tap Share in the browser bar.</li>
        <li>Choose Add to Home Screen.</li>
      </ol>
      <button
        type="button"
        className="btn"
        onClick={() => {
          writeDismissed(Date.now());
          setShown(false);
        }}
      >
        Not now
      </button>
    </section>
  );
}
