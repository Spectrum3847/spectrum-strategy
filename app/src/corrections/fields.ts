import {
  type FieldType,
  isVisible,
  type ScoutConfig,
  type ScoutField,
  type Values,
} from "../scout/config";
import { teamCodes } from "../scout/entry";
import { commentFields, isNameField } from "../team/format";
import { sameValue } from "./apply";

const fixable = new Set<FieldType>([
  "text",
  "longText",
  "number",
  "boolean",
  "select",
  "checkboxSelect",
  "range",
  "counter",
  "multiCounter",
]);

export interface FieldGroup {
  name: string;
  fields: ScoutField[];
}

function trackerCounts(field: ScoutField): ScoutField[] {
  return field.actions.map((action) => ({
    ...field,
    type: "counter",
    rawType: "counter",
    code: `${field.code}_${action.code}_count`,
    title: `${action.label} count`,
    buttons: [1],
    min: 0,
    max: null,
    step: null,
    actions: [],
    choices: null,
    visibleWhenCode: "",
    visibleWhenValue: "",
  }));
}

export function correctableGroups(config: ScoutConfig): FieldGroup[] {
  return config.sections
    .map((section) => ({
      name: section.name,
      fields: section.fields.flatMap((field) =>
        field.type === "actionTracker"
          ? trackerCounts(field)
          : fixable.has(field.type)
            ? [field]
            : [],
      ),
    }))
    .filter((group) => group.fields.length > 0);
}

export const correctableFields = (config: ScoutConfig): ScoutField[] =>
  correctableGroups(config).flatMap((g) => g.fields);

export function entryColumns(config: ScoutConfig): {
  comments: ScoutField[];
  answers: ScoutField[];
} {
  const comments = new Set(commentFields(config).map((f) => f.code));
  const fields = correctableFields(config).filter(
    (f) => !teamCodes.includes(f.code) && !isNameField(f),
  );
  return {
    comments: fields.filter((f) => comments.has(f.code)),
    answers: fields.filter((f) => !comments.has(f.code)),
  };
}

export const visibleFields = (fields: ScoutField[], values: Values) =>
  fields.filter((f) => isVisible(f, values));

export function changedFields(
  fields: ScoutField[],
  raw: Values,
  draft: Values,
): Values {
  const out: Values = {};
  for (const field of fields) {
    const value = draft[field.code];
    if (value === undefined) continue;
    if (!sameValue(raw[field.code], value)) out[field.code] = value;
  }
  return out;
}
