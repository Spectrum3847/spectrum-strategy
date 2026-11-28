import { useState } from "react";
import { useOnline } from "../ui/useOnline";
import { debugRows, debugText } from "./debugInfo";
import { packageLicenses } from "./licenses";
import { creditLinks, type Link, sourceLinks } from "./links";

function ExternalLinks({ links }: { links: Link[] }) {
  return (
    <ul className="plain link-list">
      {links.map((link) => (
        <li key={link.url}>
          <a href={link.url} target="_blank" rel="noopener noreferrer">
            <span className="link-title">{link.title}</span>
            <span className="secondary">{link.detail}</span>
          </a>
        </li>
      ))}
    </ul>
  );
}

function LicenseText({
  title,
  load,
}: {
  title: string;
  load: () => Promise<{ default: string }>;
}) {
  const [text, setText] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  return (
    <details
      className="license"
      onToggle={(e) => {
        if (!e.currentTarget.open || text !== null) return;
        load().then(
          (m) => setText(m.default),
          () => setFailed(true),
        );
      }}
    >
      <summary>{title}</summary>
      {failed ? (
        <p className="secondary">The license text could not be loaded.</p>
      ) : (
        <pre className="license-text">{text ?? "Loading."}</pre>
      )}
    </details>
  );
}

function DebugInfo() {
  const online = useOnline();
  const [copied, setCopied] = useState<"yes" | "no" | null>(null);
  const rows = debugRows({
    build: {
      version: __APP_VERSION__,
      sha: __BUILD_SHA__,
      time: __BUILD_TIME__,
    },
    browser: {
      userAgent: navigator.userAgent,
      maxTouchPoints: navigator.maxTouchPoints,
      standalone:
        window.matchMedia?.("(display-mode: standalone)").matches === true,
    },
    online,
  });
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(debugText(rows));
      setCopied("yes");
    } catch {
      setCopied("no");
    }
  };
  return (
    <section className="panel" aria-labelledby="debug-h">
      <h2 id="debug-h">Version and device</h2>
      <p className="secondary">
        The same details go with a problem report, so you can read them out when
        asking for help.
      </p>
      <dl className="rows">
        {rows.map(([label, value]) => (
          <div className="row" key={label}>
            <dt>{label}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
      <div className="actions">
        <button type="button" className="btn" onClick={copy}>
          Copy details
        </button>
      </div>
      <p className="secondary" role="status">
        {copied === "yes" && "Copied."}
        {copied === "no" && "Could not copy. Select the details and copy them."}
      </p>
    </section>
  );
}

export function About() {
  return (
    <>
      <DebugInfo />
      <section className="panel" aria-labelledby="credits-h">
        <h2 id="credits-h">Credits</h2>
        <ExternalLinks links={creditLinks} />
      </section>
      <section className="panel" aria-labelledby="source-h">
        <h2 id="source-h">Open source</h2>
        <p className="secondary">
          Spectrum Strategy is open source under the AGPL-3.0. Read the code,
          file an issue or send a pull request.
        </p>
        <ExternalLinks links={sourceLinks} />
      </section>
      <section className="panel" aria-labelledby="licenses-h">
        <h2 id="licenses-h">Licenses</h2>
        <p className="secondary">
          The packages and assets this app ships with.
        </p>
        <LicenseText
          title="Overpass font (SIL Open Font License)"
          load={() => import("../../../assets/fonts/OFL.txt?raw")}
        />
        <LicenseText
          title="WPILib field assets"
          load={() => import("../../../assets/fields/wpilib/LICENSE.txt?raw")}
        />
        <details className="license">
          <summary>Packages</summary>
          <dl className="rows">
            {Object.entries(packageLicenses).map(([name, license]) => (
              <div className="row" key={name}>
                <dt>{name}</dt>
                <dd>{license}</dd>
              </div>
            ))}
          </dl>
        </details>
      </section>
    </>
  );
}
