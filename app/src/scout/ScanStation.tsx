import { type ComponentType, useCallback, useRef, useState } from "react";
import { Link } from "react-router";
import type { ScoutConfig } from "./config";
import type { SavedEntry } from "./local";
import { type CameraProps, ScanCamera } from "./ScanCamera";
import { type Delivery, DeliveryLine } from "./ScoutForm";
import { alreadyKnown, scanToEntry } from "./scan";
import type { RemoteEntry, ScheduledMatch } from "./schedule";

export interface ScanStationProps {
  config: ScoutConfig;
  schedule: ScheduledMatch[];
  eventKey: string;
  author: { uid: string | null; displayName: string | null };
  remote: RemoteEntry[];
  saved: SavedEntry[];
  deliveryOf(entryId: string): Delivery | undefined;
  persist(doc: Record<string, unknown>, entry: SavedEntry): Promise<void>;
  Camera?: ComponentType<CameraProps>;
  repeatMs?: number;
}

type Line =
  | { n: number; kind: "added"; label: string; id: string }
  | { n: number; kind: "known"; label: string }
  | { n: number; kind: "error"; message: string };

export function ScanStation(props: ScanStationProps) {
  const { Camera = ScanCamera, repeatMs = 3000 } = props;
  const [lines, setLines] = useState<Line[]>([]);
  const seen = useRef(new Map<string, number>());
  const taken = useRef(new Set<string>());
  const count = useRef(0);
  const latest = useRef(props);
  latest.current = props;

  const add = useCallback((make: (n: number) => Line) => {
    const n = ++count.current;
    setLines((all) => [make(n), ...all]);
  }, []);

  const handle = useCallback(
    async (payload: string) => {
      const p = latest.current;
      const uid = p.author.uid;
      if (uid === null) {
        add((n) => ({
          n,
          kind: "error",
          message:
            "Signed out, so this code was not saved. Sign in and scan it again.",
        }));
        return;
      }
      const scan = scanToEntry(payload, {
        config: p.config,
        schedule: p.schedule,
        eventKey: p.eventKey,
        author: { uid, displayName: p.author.displayName ?? "" },
        now: new Date(),
      });
      if (!scan.ok) {
        add((n) => ({ n, kind: "error", message: scan.error }));
        return;
      }
      const label = `Team ${scan.entry.team}, match ${scan.entry.matchNumber}${
        scan.entry.station ? ` at ${scan.entry.station}` : ""
      }`;
      if (
        taken.current.has(scan.id) ||
        alreadyKnown(p.config, scan, payload, p.remote, p.saved)
      ) {
        add((n) => ({ n, kind: "known", label }));
        return;
      }
      taken.current.add(scan.id);
      try {
        await p.persist(scan.doc, scan.entry);
        navigator.vibrate?.(40);
        add((n) => ({ n, kind: "added", label, id: scan.id }));
      } catch {
        taken.current.delete(scan.id);
        seen.current.delete(payload);
        add((n) => ({
          n,
          kind: "error",
          message: `Could not save ${label}. Nothing was recorded, so scan it again.`,
        }));
      }
    },
    [add],
  );

  const onCode = useCallback(
    (text: string) => {
      const now = Date.now();
      const last = seen.current.get(text);
      seen.current.set(text, now);
      if (last !== undefined && now - last < repeatMs) return;
      void handle(text);
    },
    [handle, repeatMs],
  );

  const added = lines.filter((l) => l.kind === "added").length;
  const known = lines.filter((l) => l.kind === "known").length;
  const failed = lines.filter((l) => l.kind === "error").length;
  const signedIn = props.author.uid !== null;

  return (
    <div className="scout scan">
      <header className="scout-head">
        <div className="match-line">
          <h1>Scan QR</h1>
        </div>
        <p className="status-line secondary">
          <span>{props.eventKey || "No event"}</span>
          <span>Keeps scanning until you press Done</span>
        </p>
      </header>
      <div className="scan-main">
        {signedIn ? (
          <Camera onCode={onCode} />
        ) : (
          <p className="notice" role="alert">
            Sign in to import scans. An imported entry needs an author.
          </p>
        )}
        <section className="scan-results" aria-label="Scanned entries">
          <p className="status-line" aria-live="polite">
            <strong>{added} added</strong>
            <span>{known} already had</span>
            <span>{failed} not read</span>
          </p>
          {lines.length === 0 ? (
            <p className="secondary">
              Hold the other device's QR in front of the camera.
            </p>
          ) : (
            <ul className="outbox">
              {lines.map((line) => (
                <li key={line.n}>
                  {line.kind === "error" ? (
                    <span className="state" data-state="refused">
                      {line.message}
                    </span>
                  ) : (
                    <>
                      <span>{line.label}</span>
                      {line.kind === "added" ? (
                        <DeliveryLine
                          delivery={props.deliveryOf(line.id)}
                          signedIn={signedIn}
                        />
                      ) : (
                        <span className="state">Already had this entry</span>
                      )}
                    </>
                  )}
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
      <footer className="scout-foot">
        <Link to="/scout" className="btn primary big">
          Done
        </Link>
      </footer>
    </div>
  );
}
