import { fieldTypeOf } from "../scout/config";
import {
  choiceEntries,
  type Doc,
  fieldsOf,
  retiredKeys,
  sectionFields,
  sectionsOf,
  textOf,
} from "./doc";

export type NewQuestionType =
  | "text"
  | "long-text"
  | "number"
  | "boolean"
  | "document";

export const questionTypes: { value: NewQuestionType; label: string }[] = [
  { value: "text", label: "Text" },
  { value: "long-text", label: "Long text" },
  { value: "number", label: "Number" },
  { value: "boolean", label: "Boolean" },
  { value: "document", label: "Document" },
];

function camelCase(text: string, fallback: string): string {
  const words = text.split(/[^A-Za-z0-9]+/).filter((w) => w !== "");
  const joined = words
    .map((w, i) => {
      const lower = w.toLowerCase();
      return i === 0 ? lower : lower.charAt(0).toUpperCase() + lower.slice(1);
    })
    .join("");
  return joined === "" ? fallback : joined;
}

function uniqueName(base: string, taken: Set<string>): string {
  if (!taken.has(base)) return base;
  let n = 2;
  while (taken.has(`${base}${n}`)) n += 1;
  return `${base}${n}`;
}

export const codeFor = (title: string, doc: Doc) =>
  uniqueName(
    camelCase(title, "question"),
    new Set(fieldsOf(doc).map((f) => textOf(f.code))),
  );

export const choiceKeyFor = (label: string, taken: Iterable<string>) =>
  uniqueName(camelCase(label, "choice"), new Set(taken));

const withSection = (
  doc: Doc,
  index: number,
  change: (section: Doc) => Doc,
): Doc => ({
  ...doc,
  sections: sectionsOf(doc).map((s, i) => (i === index ? change(s) : s)),
});

const withFields = (doc: Doc, si: number, change: (f: Doc[]) => Doc[]): Doc =>
  withSection(doc, si, (s) => ({ ...s, fields: change(sectionFields(s)) }));

export const setReportDrawing = (doc: Doc, on: boolean): Doc => ({
  ...doc,
  report_drawing: on,
});

export const reportDrawingOn = (doc: Doc) => doc.report_drawing !== false;

export const addSection = (doc: Doc, name: string): Doc => ({
  ...doc,
  sections: [...sectionsOf(doc), { name: name.trim(), fields: [] }],
});

export const sectionIsEmpty = (doc: Doc, si: number) =>
  sectionFields(sectionsOf(doc)[si] ?? {}).length === 0;

export const removeSection = (doc: Doc, si: number): Doc =>
  sectionIsEmpty(doc, si)
    ? { ...doc, sections: sectionsOf(doc).filter((_, i) => i !== si) }
    : doc;

export interface QuestionDraft {
  title: string;
  description: string;
  required: boolean;
  type: NewQuestionType;
}

export function addQuestion(doc: Doc, si: number, draft: QuestionDraft): Doc {
  const title = draft.title.trim();
  if (title === "") return doc;
  const description = draft.description.trim();
  const field: Doc = {
    title,
    ...(description === "" ? {} : { description }),
    type: draft.type,
    required: draft.required,
    code: codeFor(title, doc),
    formResetBehavior: "reset",
    defaultValue: null,
  };
  return withFields(doc, si, (fields) => [...fields, field]);
}

export function removeQuestion(doc: Doc, si: number, fi: number): Doc {
  return withFields(doc, si, (fields) => fields.filter((_, i) => i !== fi));
}

export function moveQuestion(
  doc: Doc,
  si: number,
  fi: number,
  delta: -1 | 1,
): Doc {
  return withFields(doc, si, (fields) => {
    const to = fi + delta;
    if (to < 0 || to >= fields.length) return fields;
    const next = [...fields];
    const [moved] = next.splice(fi, 1);
    if (moved) next.splice(to, 0, moved);
    return next;
  });
}

export interface ChoiceDraft {
  key: string;
  label: string;
}

export function activeChoiceDrafts(field: Doc): ChoiceDraft[] {
  const retired = new Set(retiredKeys(field));
  return (choiceEntries(field.choices) ?? [])
    .filter(([key]) => !retired.has(key))
    .map(([key, label]) => ({ key, label }));
}

export function retiredChoiceDrafts(field: Doc): ChoiceDraft[] {
  const retired = new Set(retiredKeys(field));
  return (choiceEntries(field.choices) ?? [])
    .filter(([key]) => retired.has(key))
    .map(([key, label]) => ({ key, label }));
}

export interface QuestionPatch {
  title: string;
  description: string;
  required?: boolean;
  choices?: ChoiceDraft[];
}

function applyChoices(field: Doc, active: ChoiceDraft[]): Doc {
  const all = choiceEntries(field.choices) ?? [];
  const keep = new Set(active.map((c) => c.key));
  const retired = all.filter(([key]) => !keep.has(key));
  const next: Doc = {
    ...field,
    choices: Object.fromEntries([
      ...active.map((c) => [c.key, c.label.trim()] as const),
      ...retired,
    ]),
  };
  if (retired.length > 0) {
    next.retiredChoiceKeys = retired.map(([key]) => key);
  } else {
    delete next.retiredChoiceKeys;
  }
  return next;
}

export function updateQuestion(
  doc: Doc,
  si: number,
  fi: number,
  patch: QuestionPatch,
): Doc {
  return withFields(doc, si, (fields) =>
    fields.map((field, i) => {
      if (i !== fi) return field;
      let next: Doc = { ...field };
      const title = patch.title.trim();
      if (title !== "") next.title = title;
      const description = patch.description.trim();
      if (description === "") delete next.description;
      else next.description = description;
      if (patch.required !== undefined) next.required = patch.required;
      if (patch.choices) next = applyChoices(next, patch.choices);
      return next;
    }),
  );
}

export const isSelect = (field: Doc) =>
  fieldTypeOf(textOf(field.type, "text")) === "select";
