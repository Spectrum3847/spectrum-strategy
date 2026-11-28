import { Link } from "react-router";
import { useOutbox } from "../outbox/useOutbox";
import "./ui.css";
import { unsentCounts, unsentLines } from "./unsent";
import { useOnline } from "./useOnline";

export function UnsentBanner() {
  const unsent = unsentCounts(useOutbox());
  const online = useOnline();
  const lines = unsentLines(unsent, online);
  if (lines.length === 0) return null;
  return (
    <div
      className="unsent-banner"
      data-refused={unsent.refused > 0}
      role="status"
    >
      <div className="unsent-text">
        {lines.map((line) => (
          <p key={line}>{line}</p>
        ))}
      </div>
      <Link className="btn" to="/scout">
        Open Scout
      </Link>
    </div>
  );
}
