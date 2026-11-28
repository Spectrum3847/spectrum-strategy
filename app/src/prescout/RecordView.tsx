import { Link } from "react-router";
import "../forms/forms.css";
import type { PrescoutEntry } from "../data/parse";
import { splitLegacyLabel } from "../forms/entries";
import { isVisible, type ScoutConfig } from "../scout/config";
import { answerText } from "../scout/ScoutForm";

export function RecordView(props: {
  config: ScoutConfig;
  entry: PrescoutEntry;
  back: string;
}) {
  const values = splitLegacyLabel(props.entry.fieldValues);
  return (
    <div className="forms-page">
      <Link className="btn back" to={props.back}>
        Team {props.entry.teamNumber}
      </Link>
      <header className="forms-head">
        <h1>Team {props.entry.teamNumber} record</h1>
        <p className="secondary">
          Recorded by {props.entry.scoutName || "another scout"}. Only the
          author or a lead can change it.
        </p>
      </header>
      {props.config.sections.map((section) => {
        const fields = section.fields.filter(
          (f) =>
            isVisible(f, values) &&
            f.type !== "actionTracker" &&
            f.type !== "document",
        );
        if (fields.length === 0) return null;
        return (
          <div key={section.name} className="review-group">
            <h2>{section.name}</h2>
            <dl className="rows">
              {fields.map((f) => (
                <div key={f.code} className="review-row">
                  <dt>{f.title}</dt>
                  <dd>{answerText(f, values[f.code]) || "No answer"}</dd>
                </div>
              ))}
            </dl>
          </div>
        );
      })}
    </div>
  );
}
