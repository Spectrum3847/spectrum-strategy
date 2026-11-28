import { useId, useMemo, useState } from "react";
import { Link } from "react-router";
import type { TrexReport } from "../data/parse";
import { useTrexReports } from "../data/useCollections";
import { useTbaEvent } from "../data/useTbaEvent";
import { useDeleteGate } from "../forms/deleteEntry";
import { useIsLead } from "../forms/hooks";
import { FilterChips } from "../forms/ListParts";
import { formatTime } from "../now/matches";
import { enqueueDelete } from "../outbox/outbox";
import { DeleteButton } from "../ui/DeleteButton";
import { reportPath } from "./delivery";
import { groupReports } from "./reports";
import { TrexDrawing } from "./TrexDrawing";
import { TrexFrame } from "./TrexFrame";
import { traits } from "./traits";

function byLine(r: TrexReport): string {
  const when = Date.parse(r.updatedAt);
  return [
    `Match ${r.matchNumber}`,
    r.eventName || r.eventKey,
    r.scoutName || "Unknown scout",
    Number.isNaN(when) ? "" : formatTime(when / 1000, new Date()),
  ]
    .filter((s) => s !== "")
    .join(", ");
}

export function TrexDatabase() {
  const lead = useIsLead();
  const canDelete = useDeleteGate();
  const { eventKey } = useTbaEvent();
  const feed = useTrexReports();
  const [thisEventOnly, setThisEventOnly] = useState(true);
  const [trait, setTrait] = useState("");
  const [search, setSearch] = useState("");
  const searchId = useId();
  const scoped = thisEventOnly && eventKey !== "";
  const groups = useMemo(
    () =>
      groupReports(feed.items, {
        eventKey,
        thisEventOnly: scoped,
        trait,
        search,
      }),
    [feed.items, eventKey, scoped, trait, search],
  );

  return (
    <TrexFrame>
      {feed.failed && (
        <p className="notice" role="alert">
          Could not read the T-REx reports. The list may be incomplete.
        </p>
      )}
      <div className="trex-field">
        <label className="field-name" htmlFor={searchId}>
          Search team number
        </label>
        <input
          id={searchId}
          className="input"
          type="text"
          inputMode="numeric"
          pattern="[0-9]*"
          autoComplete="off"
          value={search}
          onChange={(e) => setSearch(e.target.value.replace(/\D/g, ""))}
        />
      </div>
      <FilterChips<string>
        label="Trait"
        value={trait}
        onPick={setTrait}
        options={[
          { key: "", text: "All traits" },
          ...traits.map((t) => ({ key: t.key, text: t.label })),
        ]}
      />
      {eventKey !== "" && (
        <FilterChips<"event" | "all">
          label="Event"
          value={thisEventOnly ? "event" : "all"}
          onPick={(k) => setThisEventOnly(k === "event")}
          options={[
            { key: "event", text: `This event (${eventKey})` },
            { key: "all", text: "All events" },
          ]}
        />
      )}
      {!feed.ready ? (
        <p className="secondary">Loading the reports.</p>
      ) : groups.length === 0 ? (
        <p className="secondary">
          {feed.items.length === 0
            ? "No T-REx reports yet."
            : "No reports match these filters."}
        </p>
      ) : (
        <ul className="plain trex-teams">
          {groups.map((g) => (
            <li key={g.team} className="trex-team">
              <details>
                <summary>
                  <span className="trex-team-name">Team {g.team}</span>
                  <span className="secondary">
                    {g.count} {g.count === 1 ? "report" : "reports"}
                  </span>
                </summary>
                <div className="trex-team-body">
                  {lead && (
                    <Link className="trex-open" to={`/teams/${g.team}`}>
                      Open team page
                    </Link>
                  )}{" "}
                  {g.traits.map((t) => (
                    <section
                      key={t.key}
                      aria-label={`${t.label}, team ${g.team}`}
                    >
                      <h3>{t.label}</h3>
                      <ul className="plain trex-reports">
                        {t.reports.map((r) => (
                          <li key={r.id}>
                            {r.rating !== null && (
                              <p className="trex-rating">
                                Rating {r.rating} of 5
                              </p>
                            )}
                            <p className="trex-body">{r.report.trim()}</p>
                            <p className="secondary">{byLine(r)}</p>
                            <TrexDrawing report={r} />
                            {canDelete(r.authorUid) && (
                              <DeleteButton
                                what={`${t.label} report for team ${g.team}`}
                                prompt="Delete this report?"
                                onConfirm={async () => {
                                  await enqueueDelete(
                                    reportPath(r.id),
                                    `T-REx report deleted, team ${g.team}`,
                                  );
                                }}
                              />
                            )}
                          </li>
                        ))}
                      </ul>
                    </section>
                  ))}
                </div>
              </details>
            </li>
          ))}
        </ul>
      )}
    </TrexFrame>
  );
}
