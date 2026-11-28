import { type AccuracyAlert, alertLine, alertsHeading } from "./alerts";
import "./aids.css";
import type { ScoutConfig } from "./config";

export function AlertBanner({
  alerts,
  config,
  onDismiss,
}: {
  alerts: AccuracyAlert[];
  config: ScoutConfig;
  onDismiss(): void;
}) {
  if (alerts.length === 0) return null;
  return (
    <section className="notice alert-banner" aria-label="Accuracy alerts">
      <div className="alert-text">
        <p>
          <strong>{alertsHeading(alerts.length)}</strong>
        </p>
        <ul className="plain">
          {alerts.map((a) => (
            <li key={a.entryId}>{alertLine(a, config)}</li>
          ))}
        </ul>
      </div>
      <button type="button" className="btn" onClick={onDismiss}>
        Dismiss
      </button>
    </section>
  );
}
