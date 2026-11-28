import { useId, useState } from "react";
import { type FieldType, fieldTypeOf } from "../scout/config";
import { type Doc, sectionFields, sectionsOf, textOf } from "./doc";
import {
  activeChoiceDrafts,
  addQuestion,
  addSection,
  type ChoiceDraft,
  choiceKeyFor,
  isSelect,
  moveQuestion,
  type NewQuestionType,
  questionTypes,
  removeQuestion,
  removeSection,
  retiredChoiceDrafts,
  sectionIsEmpty,
  updateQuestion,
} from "./edit";

export type EditMode = "view" | "text" | "full";

const typeNames: Record<FieldType, string> = {
  text: "Text",
  longText: "Long text",
  number: "Number",
  boolean: "Boolean",
  select: "Select",
  range: "Range",
  counter: "Counter",
  multiCounter: "Multi-counter",
  actionTracker: "Action tracker",
  tbaMatchNumber: "Match number (schedule)",
  tbaTeamAndRobot: "Team and station (schedule)",
  checkboxSelect: "Multi-select",
  document: "Document",
};

const typeName = (field: Doc) =>
  typeNames[fieldTypeOf(textOf(field.type, "text"))];

interface Place {
  si: number;
  fi: number;
}

function ChoicesEditor({
  active,
  retired,
  onActive,
  onRetired,
}: {
  active: ChoiceDraft[];
  retired: ChoiceDraft[];
  onActive(next: ChoiceDraft[]): void;
  onRetired(next: ChoiceDraft[]): void;
}) {
  const [label, setLabel] = useState("");
  const rename = (i: number, text: string) =>
    onActive(active.map((c, j) => (i === j ? { ...c, label: text } : c)));
  const move = (i: number, delta: -1 | 1) => {
    const next = [...active];
    const [item] = next.splice(i, 1);
    if (item) next.splice(i + delta, 0, item);
    onActive(next);
  };
  const remove = (i: number) => {
    const gone = active[i];
    if (!gone) return;
    onActive(active.filter((_, j) => j !== i));
    onRetired([...retired, gone]);
  };
  const restore = (i: number) => {
    const back = retired[i];
    if (!back) return;
    onRetired(retired.filter((_, j) => j !== i));
    onActive([...active, back]);
  };
  const add = () => {
    const text = label.trim();
    if (text === "") return;
    const key = choiceKeyFor(text, [
      ...active.map((c) => c.key),
      ...retired.map((c) => c.key),
    ]);
    onActive([...active, { key, label: text }]);
    setLabel("");
  };
  return (
    <fieldset className="ce-choices">
      <legend>Choices</legend>
      <ul className="ce-list">
        {active.map((choice, i) => (
          <li key={choice.key} className="ce-choice">
            <input
              className="input"
              aria-label={`Label for choice ${choice.key}`}
              value={choice.label}
              onChange={(e) => rename(i, e.target.value)}
            />
            <button
              type="button"
              className="btn"
              aria-label={`Move ${choice.label} up`}
              disabled={i === 0}
              onClick={() => move(i, -1)}
            >
              Up
            </button>
            <button
              type="button"
              className="btn"
              aria-label={`Move ${choice.label} down`}
              disabled={i === active.length - 1}
              onClick={() => move(i, 1)}
            >
              Down
            </button>
            <button
              type="button"
              className="btn"
              aria-label={`Remove ${choice.label}`}
              disabled={active.length <= 1}
              onClick={() => remove(i)}
            >
              Remove
            </button>
          </li>
        ))}
      </ul>
      <p className="secondary">
        A removed choice is retired: answers already captured keep its label,
        and it is no longer offered. The last choice cannot be removed.
      </p>
      {retired.length > 0 && (
        <ul className="ce-list">
          {retired.map((choice, i) => (
            <li key={choice.key} className="ce-choice">
              <span className="ce-grow">{choice.label} (retired)</span>
              <button
                type="button"
                className="btn"
                aria-label={`Restore ${choice.label}`}
                onClick={() => restore(i)}
              >
                Restore
              </button>
            </li>
          ))}
        </ul>
      )}
      <div className="ce-choice">
        <input
          className="input"
          aria-label="New choice label"
          placeholder="New choice"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
        />
        <button
          type="button"
          className="btn"
          disabled={label.trim() === ""}
          onClick={add}
        >
          Add choice
        </button>
      </div>
    </fieldset>
  );
}

interface FormProps {
  heading: string;
  initial?: Doc;
  full: boolean;
  submitLabel: string;
  onSubmit(values: {
    title: string;
    description: string;
    required: boolean;
    type: NewQuestionType;
    choices: { active: ChoiceDraft[] } | null;
  }): void;
  onCancel(): void;
}

function QuestionForm({
  heading,
  initial,
  full,
  submitLabel,
  onSubmit,
  onCancel,
}: FormProps) {
  const id = useId();
  const [title, setTitle] = useState(textOf(initial?.title));
  const [description, setDescription] = useState(textOf(initial?.description));
  const [required, setRequired] = useState(initial?.required === true);
  const [type, setType] = useState<NewQuestionType>("text");
  const withChoices = initial !== undefined && full && isSelect(initial);
  const [active, setActive] = useState(
    initial ? activeChoiceDrafts(initial) : [],
  );
  const [retired, setRetired] = useState(
    initial ? retiredChoiceDrafts(initial) : [],
  );
  const blankChoice = active.some((c) => c.label.trim() === "");
  return (
    <form
      className="ce-form"
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit({
          title,
          description,
          required,
          type,
          choices: withChoices ? { active } : null,
        });
      }}
    >
      <h4>{heading}</h4>
      <label htmlFor={`${id}-title`}>{full ? "Question" : "Title"}</label>
      <input
        id={`${id}-title`}
        className="input"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
      />
      <label htmlFor={`${id}-desc`}>
        {full ? "Hint text (optional)" : "Description"}
      </label>
      <textarea
        id={`${id}-desc`}
        className="input"
        rows={2}
        value={description}
        onChange={(e) => setDescription(e.target.value)}
      />
      {full && initial === undefined && (
        <>
          <label htmlFor={`${id}-type`}>Type</label>
          <select
            id={`${id}-type`}
            className="input"
            value={type}
            onChange={(e) => setType(e.target.value as NewQuestionType)}
          >
            {questionTypes.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
        </>
      )}
      {full && (
        <label className="ce-check">
          <input
            type="checkbox"
            checked={required}
            onChange={(e) => setRequired(e.target.checked)}
          />
          <span>Required</span>
        </label>
      )}
      {withChoices && (
        <ChoicesEditor
          active={active}
          retired={retired}
          onActive={setActive}
          onRetired={setRetired}
        />
      )}
      <div className="actions">
        <button
          type="submit"
          className="btn primary"
          disabled={
            (initial === undefined && title.trim() === "") || blankChoice
          }
        >
          {submitLabel}
        </button>
        <button type="button" className="btn" onClick={onCancel}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export function QuestionList({
  doc,
  mode,
  onChange,
}: {
  doc: Doc;
  mode: EditMode;
  onChange(doc: Doc): void;
}) {
  const [editing, setEditing] = useState<Place | null>(null);
  const [adding, setAdding] = useState<number | null>(null);
  const [sectionName, setSectionName] = useState("");
  const full = mode === "full";
  const sections = sectionsOf(doc);
  return (
    <div className="ce-sections">
      {sections.map((section, si) => {
        const fields = sectionFields(section);
        const name = textOf(section.name) || "Untitled section";
        return (
          // biome-ignore lint/suspicious/noArrayIndexKey: sections are positional
          <section key={si} className="ce-section" aria-label={name}>
            <h4>{name}</h4>
            {fields.length === 0 && (
              <p className="secondary">No questions in this section.</p>
            )}
            <ul className="ce-list">
              {fields.map((field, fi) => {
                const title = textOf(field.title) || textOf(field.code);
                const here = editing?.si === si && editing.fi === fi;
                return (
                  // biome-ignore lint/suspicious/noArrayIndexKey: codes can repeat
                  <li key={fi} className="ce-field">
                    {here ? (
                      <QuestionForm
                        heading={`Edit ${title}`}
                        initial={field}
                        full={full}
                        submitLabel="Apply"
                        onCancel={() => setEditing(null)}
                        onSubmit={(v) => {
                          onChange(
                            updateQuestion(doc, si, fi, {
                              title: v.title,
                              description: v.description,
                              ...(full ? { required: v.required } : {}),
                              ...(v.choices
                                ? { choices: v.choices.active }
                                : {}),
                            }),
                          );
                          setEditing(null);
                        }}
                      />
                    ) : (
                      <div className="ce-row">
                        <div className="ce-grow">
                          <span className="ce-title">{title}</span>
                          <span className="secondary">
                            {typeName(field)}
                            {field.required === true ? ", required" : ""}
                            {mode === "text" && `, code ${textOf(field.code)}`}
                          </span>
                          {isSelect(field) && mode === "view" && (
                            <span className="secondary">
                              {activeChoiceDrafts(field)
                                .map((c) => c.label)
                                .join(", ")}
                            </span>
                          )}
                        </div>
                        {mode !== "view" && (
                          <div className="ce-tools">
                            <button
                              type="button"
                              className="btn"
                              aria-label={`Edit ${title}`}
                              onClick={() => {
                                setAdding(null);
                                setEditing({ si, fi });
                              }}
                            >
                              Edit
                            </button>
                            {full && (
                              <>
                                <button
                                  type="button"
                                  className="btn"
                                  aria-label={`Move ${title} up`}
                                  disabled={fi === 0}
                                  onClick={() =>
                                    onChange(moveQuestion(doc, si, fi, -1))
                                  }
                                >
                                  Up
                                </button>
                                <button
                                  type="button"
                                  className="btn"
                                  aria-label={`Move ${title} down`}
                                  disabled={fi === fields.length - 1}
                                  onClick={() =>
                                    onChange(moveQuestion(doc, si, fi, 1))
                                  }
                                >
                                  Down
                                </button>
                                <button
                                  type="button"
                                  className="btn"
                                  aria-label={`Remove ${title}`}
                                  onClick={() =>
                                    onChange(removeQuestion(doc, si, fi))
                                  }
                                >
                                  Remove
                                </button>
                              </>
                            )}
                          </div>
                        )}
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
            {full && adding === si && (
              <QuestionForm
                heading="Add question"
                full
                submitLabel="Add question"
                onCancel={() => setAdding(null)}
                onSubmit={(v) => {
                  onChange(addQuestion(doc, si, v));
                  setAdding(null);
                }}
              />
            )}
            {full && adding !== si && (
              <div className="actions">
                <button
                  type="button"
                  className="btn"
                  aria-label={`Add question to ${name}`}
                  onClick={() => {
                    setEditing(null);
                    setAdding(si);
                  }}
                >
                  Add question
                </button>
                <button
                  type="button"
                  className="btn"
                  aria-label={`Delete section ${name}`}
                  disabled={!sectionIsEmpty(doc, si)}
                  onClick={() => onChange(removeSection(doc, si))}
                >
                  Delete section
                </button>
                {!sectionIsEmpty(doc, si) && (
                  <span className="secondary">
                    Remove its questions first to delete the section.
                  </span>
                )}
              </div>
            )}
          </section>
        );
      })}
      {full && (
        <form
          className="ce-add-section"
          onSubmit={(e) => {
            e.preventDefault();
            if (sectionName.trim() === "") return;
            onChange(addSection(doc, sectionName));
            setSectionName("");
          }}
        >
          <input
            className="input"
            aria-label="Section name"
            placeholder="New section name"
            value={sectionName}
            onChange={(e) => setSectionName(e.target.value)}
          />
          <button
            type="submit"
            className="btn"
            disabled={sectionName.trim() === ""}
          >
            Add section
          </button>
        </form>
      )}
    </div>
  );
}
