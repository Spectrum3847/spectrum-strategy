import { useState } from "react";
import { isLead } from "../auth/roles";
import { useRoles } from "../auth/rolesContext";
import { formatTime } from "../now/matches";
import { useOutbox } from "../outbox/useOutbox";
import { TeamLink } from "../ui/TeamLink";
import { useOnline } from "../ui/useOnline";
import {
  isAssignedTo,
  mergeSections,
  type Section,
  totalTeams,
} from "./assignments";
import { exportText } from "./edit";
import { TrexEditor } from "./TrexEditor";
import { TrexFrame } from "./TrexFrame";
import { useTrexTables } from "./useAssignments";
import { useTableEdits } from "./useTableEdits";

const isTeamNumber = (s: string) => /^\d{1,5}$/.test(s.trim());

function SectionCard({ section, mine }: { section: Section; mine: boolean }) {
  return (
    <li className="trex-assign" data-mine={mine}>
      <h3>
        {section.name || "Untitled"}
        {mine && <span className="trex-you">You are assigned</span>}
      </h3>
      <div className="trex-assign-cols">
        <div>
          <h4>Scouters</h4>
          {section.scouters.length === 0 ? (
            <p className="secondary">No one assigned yet</p>
          ) : (
            <ul className="plain">
              {section.scouters.map((name) => (
                <li key={name}>{name}</li>
              ))}
            </ul>
          )}
        </div>
        <div>
          <h4>Teams</h4>
          {section.teams.length === 0 ? (
            <p className="secondary">No teams yet</p>
          ) : (
            <ul className="plain trex-assign-teams">
              {section.teams.map((team) => (
                <li key={team}>
                  {isTeamNumber(team) ? <TeamLink team={Number(team)} /> : team}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </li>
  );
}

export function TrexAssignments() {
  const roles = useRoles();
  const tables = useTrexTables();
  const edits = useTableEdits(tables);
  const outbox = useOutbox();
  const online = useOnline();
  const [editing, setEditing] = useState(false);
  const [copied, setCopied] = useState<"" | "done" | "failed">("");
  const me = roles.status === "ready" ? roles.displayName : "";
  const lead = roles.status === "ready" && isLead(roles.roles);
  const loaded = tables.ready && !tables.failed && !(tables.missing && !online);
  const canEdit = lead && edits.canSave && loaded;
  const { assignments, teamList } = edits;
  const sections = mergeSections(assignments.columns, teamList.columns);
  const stamp = [assignments.updatedAt, teamList.updatedAt]
    .map((s) => Date.parse(s))
    .filter((n) => !Number.isNaN(n) && n > 0)
    .sort((a, b) => b - a)[0];
  const teamCount = totalTeams(teamList.columns);

  async function copy() {
    try {
      await navigator.clipboard.writeText(exportText(assignments, teamList));
      setCopied("done");
    } catch {
      setCopied("failed");
    }
  }

  return (
    <TrexFrame>
      {tables.failed && (
        <p className="notice" role="alert">
          Could not read the T-REx assignments. This may be an older copy.
        </p>
      )}
      {!tables.ready ? (
        <p className="secondary">Loading the assignments.</p>
      ) : (
        <>
          <div className="trex-toolbar">
            {canEdit && (
              <button
                type="button"
                className="btn primary"
                aria-pressed={editing}
                onClick={() => setEditing(!editing)}
              >
                {editing ? "Done" : "Edit"}
              </button>
            )}
            <button type="button" className="btn" onClick={() => void copy()}>
              Copy as text
            </button>
            <span className="secondary" role="status">
              {copied === "done" && "Copied"}
              {copied === "failed" &&
                "Could not copy. This browser blocked the clipboard."}
            </span>
          </div>
          {lead && tables.missing && !online && (
            <p className="secondary">
              Connect once to load the current assignments before editing.
            </p>
          )}
          {editing && canEdit ? (
            <TrexEditor edits={edits} outbox={outbox} />
          ) : sections.length === 0 ? (
            <p className="secondary">
              {tables.missing
                ? "No assignments on this device yet. Open this screen once while online to load them."
                : "No T-REx traits have been added yet."}
            </p>
          ) : (
            <>
              {teamList.title && <p className="secondary">{teamList.title}</p>}
              <ul className="plain trex-assigns">
                {sections.map((s, i) => (
                  <SectionCard
                    // biome-ignore lint/suspicious/noArrayIndexKey: sections can repeat a name and scouters, and their order is the table's
                    key={i}
                    section={s}
                    mine={isAssignedTo(s, me)}
                  />
                ))}
              </ul>
              <p className="secondary">
                {teamCount > 0 && `Total teams: ${teamCount}. `}
                {stamp !== undefined &&
                  `Updated ${formatTime(stamp / 1000, new Date())}.`}
              </p>
            </>
          )}
        </>
      )}
    </TrexFrame>
  );
}
