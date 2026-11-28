import { type Doc, isRecord, revisionOf } from "./doc";

function parse(json: string | null): Doc | null {
  if (!json) return null;
  try {
    const value: unknown = JSON.parse(json);
    return isRecord(value) ? value : null;
  } catch {
    return null;
  }
}

export function pickActive(bundled: Doc, copies: (string | null)[]): Doc {
  let active = bundled;
  for (const json of copies) {
    const doc = parse(json);
    if (doc && revisionOf(doc) > revisionOf(active)) active = doc;
  }
  return active;
}
