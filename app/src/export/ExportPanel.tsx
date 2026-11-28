import { useState } from "react";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { useCorrectedEntries } from "../corrections/useCorrectedEntries";
import { useTbaEvent } from "../data/useTbaEvent";
import { useScoutData } from "../scout/ScoutData";
import { buildScoutCsv, exportFileName } from "./csv";
import { downloadCsv } from "./download";
import { buildSummaryCsv, summaryFileName } from "./summary";
import "./export.css";

export function ExportPanel() {
  const roles = useRoles();
  const { config, eventKey } = useScoutData();
  const feed = useCorrectedEntries(eventKey);
  const tba = useTbaEvent();
  const [hideNames, setHideNames] = useState(true);
  const [includeComments, setIncludeComments] = useState(false);
  const count = feed.items.length;
  const download = () =>
    downloadCsv(
      exportFileName(eventKey),
      buildScoutCsv(config, feed.items, eventKey, {
        hideNames,
        includeComments,
      }),
    );

  const downloadSummary = () =>
    downloadCsv(
      summaryFileName(eventKey),
      buildSummaryCsv(
        config,
        feed.items,
        tba.teams.map((t) => t.number),
        eventKey,
      ),
    );

  if (roles.status !== "ready" || !isLead(roles.roles)) return null;

  const summary =
    eventKey === ""
      ? "Set an event above before exporting."
      : !feed.ready
        ? "Loading entries."
        : `${count} ${count === 1 ? "entry" : "entries"} for ${eventKey}.`;

  return (
    <section className="panel" aria-labelledby="export-h">
      <h2 id="export-h">Export</h2>
      <p className="secondary">
        Match scout entries for the active event as a CSV file.
      </p>
      <div className="export-options">
        <label className="export-option">
          <input
            type="checkbox"
            checked={hideNames}
            onChange={(e) => setHideNames(e.target.checked)}
          />
          <span>
            Hide scout names
            <span className="secondary">
              Names become Scout 1, Scout 2 and so on.
            </span>
          </span>
        </label>
        <label className="export-option">
          <input
            type="checkbox"
            checked={includeComments}
            onChange={(e) => setIncludeComments(e.target.checked)}
          />
          <span>
            Include comments
            <span className="secondary">
              Free-text answers can name people.
            </span>
          </span>
        </label>
      </div>
      <p role="status">{summary}</p>
      {feed.failed && (
        <p className="notice" role="alert">
          Entries could not be fully loaded, so the file may be incomplete.
        </p>
      )}
      <div className="actions">
        <button
          type="button"
          className="btn primary"
          disabled={eventKey === "" || count === 0}
          onClick={download}
        >
          Download CSV
        </button>
      </div>
      <p className="secondary">
        The team summary has one row per team: matches scouted, the typical and
        best auto and teleop totals, and climb success rates. It carries no
        scout names.
      </p>
      <div className="actions">
        <button
          type="button"
          className="btn"
          disabled={eventKey === "" || (count === 0 && tba.teams.length === 0)}
          onClick={downloadSummary}
        >
          Download team summary
        </button>
      </div>
    </section>
  );
}
