import { fieldTypeOf } from "../scout/config";
import {
  choiceEntries,
  type Doc,
  delimiterOf,
  fieldsOf,
  isRecord,
  retiredKeys,
  revisionOf,
  sectionsOf,
  textOf,
} from "./doc";
import { duplicateOptionMessage } from "./validate";

export const maxConfigChars = 900_000;

export const nextRevision = (incoming: Doc, activeRevision: number) =>
  Math.max(revisionOf(incoming), activeRevision) + 1;

function reconcileField(field: Doc, live: Doc | undefined): Doc {
  const incoming = choiceEntries(field.choices);
  const before = live ? choiceEntries(live.choices) : null;
  if (!incoming || !before) return field;
  const merged = [...incoming];
  const present = new Set(incoming.map(([key]) => key));
  const retired = new Set(retiredKeys(field).filter((k) => present.has(k)));
  for (const [key, label] of before) {
    if (present.has(key)) continue;
    merged.push([key, label]);
    retired.add(key);
  }
  const next: Doc = { ...field, choices: Object.fromEntries(merged) };
  const ordered = merged.map(([key]) => key).filter((k) => retired.has(k));
  if (ordered.length > 0) next.retiredChoiceKeys = ordered;
  else delete next.retiredChoiceKeys;
  return next;
}

export function reconcileChoices(incoming: Doc, live: Doc | null): Doc {
  if (!live) return incoming;
  const liveByCode = new Map<string, Doc>();
  for (const field of fieldsOf(live)) {
    const code = textOf(field.code);
    if (code !== "" && !liveByCode.has(code)) liveByCode.set(code, field);
  }
  const sections = Array.isArray(incoming.sections)
    ? incoming.sections.map((section) =>
        isRecord(section) && Array.isArray(section.fields)
          ? {
              ...section,
              fields: section.fields.map((field) =>
                isRecord(field)
                  ? reconcileField(field, liveByCode.get(textOf(field.code)))
                  : field,
              ),
            }
          : section,
      )
    : incoming.sections;
  return { ...incoming, sections };
}

export interface Changes {
  revisionFrom: number | null;
  revisionTo: number;
  settings: string[];
  sectionsAdded: string[];
  sectionsRemoved: string[];
  fieldsAdded: string[];
  fieldsRemoved: string[];
  fieldsEdited: string[];
  choicesAdded: string[];
  choicesRetired: string[];
  choicesRestored: string[];
}

const settingNames: Record<string, string> = {
  title: "Title",
  page_title: "Subtitle",
  delimiter: "Delimiter",
  report_drawing: "Report drawing",
};

const fieldLabel = (field: Doc) =>
  textOf(field.title).trim() || textOf(field.code) || "Untitled";

const byCode = (doc: Doc) => {
  const map = new Map<string, Doc>();
  for (const field of fieldsOf(doc)) {
    const code = textOf(field.code);
    if (!map.has(code)) map.set(code, field);
  }
  return map;
};

const sectionNames = (doc: Doc) =>
  sectionsOf(doc).map((s) => textOf(s.name) || "Untitled section");

const withoutChoices = (field: Doc) => {
  const { choices: _c, retiredChoiceKeys: _r, ...rest } = field;
  return JSON.stringify(rest);
};

export function describeChanges(
  live: Doc | null,
  next: Doc,
  revisionFrom: number | null,
): Changes {
  const changes: Changes = {
    revisionFrom,
    revisionTo: revisionOf(next),
    settings: [],
    sectionsAdded: [],
    sectionsRemoved: [],
    fieldsAdded: [],
    fieldsRemoved: [],
    fieldsEdited: [],
    choicesAdded: [],
    choicesRetired: [],
    choicesRestored: [],
  };
  const before = live ?? {};
  for (const key of new Set([...Object.keys(before), ...Object.keys(next)])) {
    if (key === "sections" || key === "revision") continue;
    const read = key === "delimiter" ? delimiterOf : (v: unknown) => v;
    if (JSON.stringify(read(before[key])) !== JSON.stringify(read(next[key]))) {
      changes.settings.push(settingNames[key] ?? key);
    }
  }
  const oldNames = sectionNames(before);
  const newNames = sectionNames(next);
  changes.sectionsAdded = newNames.filter((n) => !oldNames.includes(n));
  changes.sectionsRemoved = oldNames.filter((n) => !newNames.includes(n));

  const oldFields = byCode(before);
  const newFields = byCode(next);
  for (const [code, field] of newFields) {
    const old = oldFields.get(code);
    if (!old) {
      changes.fieldsAdded.push(fieldLabel(field));
      continue;
    }
    const label = fieldLabel(field);
    const after = choiceEntries(field.choices) ?? [];
    const prior = new Map(choiceEntries(old.choices) ?? []);
    const nowRetired = new Set(retiredKeys(field));
    const wasRetired = new Set(retiredKeys(old));
    let edited = withoutChoices(old) !== withoutChoices(field);
    for (const [key, text] of after) {
      if (!prior.has(key)) {
        changes.choicesAdded.push(`${label}: ${text}`);
        continue;
      }
      if (prior.get(key) !== text) edited = true;
      if (nowRetired.has(key) && !wasRetired.has(key)) {
        changes.choicesRetired.push(`${label}: ${text}`);
      }
      if (!nowRetired.has(key) && wasRetired.has(key)) {
        changes.choicesRestored.push(`${label}: ${text}`);
      }
    }
    if (edited) changes.fieldsEdited.push(label);
  }
  for (const [code, field] of oldFields) {
    if (!newFields.has(code)) changes.fieldsRemoved.push(fieldLabel(field));
  }
  return changes;
}

export const hasChanges = (c: Changes) =>
  c.settings.length +
    c.sectionsAdded.length +
    c.sectionsRemoved.length +
    c.fieldsAdded.length +
    c.fieldsRemoved.length +
    c.fieldsEdited.length +
    c.choicesAdded.length +
    c.choicesRetired.length +
    c.choicesRestored.length >
  0;

export type Prepared =
  | { ok: true; doc: Doc; configJson: string; changes: Changes }
  | { ok: false; error: string };

function labelClash(doc: Doc): string | null {
  for (const field of fieldsOf(doc)) {
    if (fieldTypeOf(textOf(field.type, "text")) !== "select") continue;
    const entries = choiceEntries(field.choices);
    if (!entries || retiredKeys(field).length === 0) continue;
    const labels = entries.map(([, label]) => label);
    if (new Set(labels).size === labels.length) continue;
    const code = textOf(field.code);
    return `${duplicateOptionMessage(code)} A choice removed from this field is kept as retired under its old label, so give the new choice a different label.`;
  }
  return null;
}

export function prepareSave(
  incoming: Doc,
  live: Doc | null,
  activeRevision: number,
): Prepared {
  const reconciled = reconcileChoices(incoming, live);
  const doc: Doc = {
    ...reconciled,
    delimiter: delimiterOf(reconciled.delimiter),
    revision: nextRevision(incoming, activeRevision),
  };
  const clash = labelClash(doc);
  if (clash) return { ok: false, error: clash };
  const configJson = JSON.stringify(doc);
  if (configJson.length > maxConfigChars) {
    return {
      ok: false,
      error: "This config is too large to store. Remove some fields or text.",
    };
  }
  return {
    ok: true,
    doc,
    configJson,
    changes: describeChanges(live, doc, live ? activeRevision : null),
  };
}
