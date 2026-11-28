import { useEffect, useState } from "react";
import { AiCard } from "../assistant/AiCard";
import {
  type MatchResult,
  postMatchKey,
  postMatchRequest,
} from "../assistant/postMatch";
import { provenance } from "../assistant/queue";
import { matchIdOf } from "../match/brief";
import { useOutbox } from "../outbox/useOutbox";
import { DeliveryLine } from "../scout/ScoutForm";
import {
  type Author,
  emptyReport,
  isEmptyReport,
  maxSection,
  type PostMatchReport,
  reportId,
  type Sections,
  sectionHints,
  sectionKeys,
  sectionLabels,
} from "./postMatch";
import {
  reportPath,
  savePostMatchReport,
  usePostMatchReports,
} from "./usePostMatchReports";
import "./reports.css";

interface Props {
  eventKey: string;
  matchKey: string;
  label: string;
  canEdit: boolean;
  signedIn: boolean;
  author: Author;
  match: MatchResult;
  us: number | null;
}

const sectionsOf = (report: PostMatchReport): Sections => ({
  auto: report.auto,
  teleop: report.teleop,
  endgame: report.endgame,
  notes: report.notes,
});

function Form({
  report,
  label,
  canEdit,
  signedIn,
  author,
}: {
  report: PostMatchReport;
  label: string;
  canEdit: boolean;
  signedIn: boolean;
  author: Author;
}) {
  const outbox = useOutbox();
  const sent = outbox.find((i) => i.path === reportPath(report.id));
  const [draft, setDraft] = useState(() => sectionsOf(report));
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  // biome-ignore lint/correctness/useExhaustiveDependencies: only a new revision resets the form.
  useEffect(() => {
    if (!dirty) setDraft(sectionsOf(report));
  }, [report.updatedMs]);

  const save = async () => {
    setBusy(true);
    setFailed(false);
    try {
      await savePostMatchReport(report, draft, author, `Report for ${label}`);
      setDirty(false);
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  };

  const canSave = signedIn && author.uid !== "";

  return (
    <>
      {!canEdit && (
        <p className="secondary">
          Only strategy leads and admins can write this.
          {isEmptyReport(report) && " Nobody has written it up yet."}
        </p>
      )}
      <div className="report-form">
        {sectionKeys.map((key) => (
          <label className="report-field" key={key}>
            <span className="field-name">{sectionLabels[key]}</span>
            <textarea
              className="input"
              rows={3}
              maxLength={maxSection}
              placeholder={sectionHints[key]}
              readOnly={!canEdit}
              value={draft[key]}
              onChange={(e) => {
                setDraft({ ...draft, [key]: e.target.value });
                setDirty(true);
              }}
            />
          </label>
        ))}
      </div>
      {report.authorDisplayName !== "" && (
        <p className="secondary">Last written by {report.authorDisplayName}</p>
      )}
      {canEdit && (
        <div className="actions">
          <button
            type="button"
            className="btn primary"
            disabled={!dirty || busy || !canSave}
            onClick={() => void save()}
          >
            Save report
          </button>
          {(sent || failed) && (
            <span className="match-delivery" role="status">
              {failed ? (
                <span className="state" data-state="refused">
                  Could not save on this device. Try again.
                </span>
              ) : (
                <DeliveryLine
                  delivery={
                    sent
                      ? {
                          status: sent.status,
                          ...(sent.error ? { error: sent.error } : {}),
                        }
                      : undefined
                  }
                  signedIn={signedIn}
                />
              )}
            </span>
          )}
        </div>
      )}
      {canEdit && !canSave && (
        <p className="secondary">Sign in to save the report.</p>
      )}
    </>
  );
}

export function PostMatchSection(props: Props) {
  const reports = usePostMatchReports();
  const matchId = matchIdOf(props.eventKey, props.matchKey);
  const id = reportId(props.eventKey, matchId);
  const report =
    reports.items.find((r) => r.id === id) ??
    emptyReport(props.eventKey, matchId);
  return (
    <section className="match-section" aria-labelledby="report-h">
      <h2 id="report-h">Post match report</h2>
      {reports.failed && (
        <p className="notice" role="status">
          Could not read the saved report. What shows may be out of date.
        </p>
      )}
      <Form
        key={report.id}
        report={report}
        label={props.label}
        canEdit={props.canEdit}
        signedIn={props.signedIn}
        author={props.author}
      />
      <AiCard
        title="AI report summary"
        askLabel="Summarise this report"
        idle="Ask a team device with an AI model to summarise the saved report and the result."
        describe={(summary, now) =>
          `${provenance({ ...summary, coverage: null }, 0, "sections", now)} Check it against the report above.`
        }
        cacheKey={postMatchKey(props.eventKey, matchId)}
        request={postMatchRequest(
          props.eventKey,
          matchId,
          report,
          props.match,
          props.us,
        )}
        lead={props.canEdit}
        uid={props.author.uid}
      />
    </section>
  );
}
