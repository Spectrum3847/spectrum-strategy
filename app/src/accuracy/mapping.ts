export const mappingPath = "appConfig/accuracyMapping";

export type MappingDoc = Record<string, unknown>;

export function starterMapping(year: number): MappingDoc {
  return {
    year,
    perFieldTolerancePct: 50,
    perFieldAbsoluteMin: 2,
    minWrongFields: 3,
    minWrongFraction: 0.5,
    egregiousAbsMin: 5,
    egregiousPct: 200,
    mappings: [],
  };
}

export const mappingText = (doc: MappingDoc) => JSON.stringify(doc, null, 2);

export type ParsedMapping =
  | { ok: true; doc: MappingDoc }
  | { ok: false; error: string };

export function parseMappingText(text: string): ParsedMapping {
  let decoded: unknown;
  try {
    decoded = JSON.parse(text);
  } catch (error) {
    return {
      ok: false,
      error: `Not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    };
  }
  if (
    typeof decoded !== "object" ||
    decoded === null ||
    Array.isArray(decoded)
  ) {
    return { ok: false, error: "The top level must be a JSON object." };
  }
  const doc = decoded as MappingDoc;
  if (!Array.isArray(doc.mappings)) {
    return { ok: false, error: '"mappings" must be an array.' };
  }
  return { ok: true, doc };
}

export function mappingRows(doc: MappingDoc): [string, string][] {
  const show = (key: string, fallback: number | string) =>
    String(doc[key] ?? fallback);
  return [
    ["Year", show("year", "none")],
    ["Compared fields", String((doc.mappings as unknown[]).length)],
    ["Field tolerance %", show("perFieldTolerancePct", 50)],
    ["Field absolute minimum", show("perFieldAbsoluteMin", 2)],
    ["Alert at wrong fields", show("minWrongFields", 3)],
    ["Alert at wrong fraction", show("minWrongFraction", 0.5)],
    ["Egregious absolute minimum", show("egregiousAbsMin", 5)],
    ["Egregious deviation %", show("egregiousPct", 200)],
  ];
}

export function readMapping(data: unknown): MappingDoc | null {
  if (typeof data !== "object" || data === null || Array.isArray(data)) {
    return null;
  }
  const doc = data as MappingDoc;
  return Array.isArray(doc.mappings) ? doc : null;
}
