export type Doc = Record<string, unknown>;

export type FormId = "scout" | "pit" | "prescout";

export const formIds: FormId[] = ["scout", "pit", "prescout"];

export const formName: Record<FormId, string> = {
  scout: "Scout form",
  pit: "Pit form",
  prescout: "Prescout form",
};

export const docIdOf = {
  scout: "scoutConfig",
  pit: "pitScoutConfig",
  prescout: "prescoutConfig",
} as const;

export const configPath = (form: FormId) => `appConfig/${docIdOf[form]}`;

export const isRecord = (v: unknown): v is Doc =>
  typeof v === "object" && v !== null && !Array.isArray(v);

export const sectionsOf = (doc: Doc): Doc[] =>
  Array.isArray(doc.sections) ? doc.sections.filter(isRecord) : [];

export const sectionFields = (section: Doc): Doc[] =>
  Array.isArray(section.fields) ? section.fields.filter(isRecord) : [];

export const fieldsOf = (doc: Doc): Doc[] =>
  sectionsOf(doc).flatMap(sectionFields);

export const textOf = (v: unknown, fallback = ""): string =>
  typeof v === "string" ? v : fallback;

export const revisionOf = (doc: Doc): number =>
  typeof doc.revision === "number" ? Math.trunc(doc.revision) : 0;

export function delimiterOf(raw: unknown): string {
  return typeof raw === "string" && raw.length >= 1 && raw.length <= 4
    ? raw
    : "\t";
}

export const normalizeTypeName = (s: string) =>
  s.toLowerCase().replace(/[-_]/g, "");

export function choiceEntries(raw: unknown): [string, string][] | null {
  if (isRecord(raw)) return Object.entries(raw).map(([k, v]) => [k, String(v)]);
  if (Array.isArray(raw)) return raw.map((v) => [String(v), String(v)]);
  return null;
}

export const retiredKeys = (field: Doc): string[] =>
  Array.isArray(field.retiredChoiceKeys)
    ? field.retiredChoiceKeys.map(String)
    : [];
