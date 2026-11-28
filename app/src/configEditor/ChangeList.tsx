import { type Changes, hasChanges } from "./revise";

const list = (items: string[]) => items.join("; ");

export function ChangeList({ changes }: { changes: Changes }) {
  const rows: [string, string][] = [];
  const add = (label: string, items: string[]) => {
    if (items.length > 0) rows.push([label, list(items)]);
  };
  add("Settings changed", changes.settings);
  add("Sections added", changes.sectionsAdded);
  add("Sections removed", changes.sectionsRemoved);
  add("Fields added", changes.fieldsAdded);
  add("Fields removed", changes.fieldsRemoved);
  add("Fields edited", changes.fieldsEdited);
  add("Choices added", changes.choicesAdded);
  add("Choices retired", changes.choicesRetired);
  add("Choices restored", changes.choicesRestored);
  return (
    <dl className="rows">
      <dt>Revision</dt>
      <dd>
        {changes.revisionFrom === null
          ? `New, ${changes.revisionTo}`
          : `${changes.revisionFrom} to ${changes.revisionTo}`}
      </dd>
      {rows.map(([label, text]) => (
        <div key={label} className="ce-change">
          <dt>{label}</dt>
          <dd>{text}</dd>
        </div>
      ))}
      {!hasChanges(changes) && (
        <>
          <dt>Fields</dt>
          <dd>No changes to settings, sections or fields.</dd>
        </>
      )}
    </dl>
  );
}
