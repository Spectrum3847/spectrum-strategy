import type { Correction } from "../data/corrections";
import type { Values } from "../scout/config";

export type Corrected<T extends { fieldValues: Values }> = T & {
  rawValues: Values;
  corrected: string[];
  correction: Correction | null;
};

export const sameValue = (a: unknown, b: unknown) =>
  String(a ?? "") === String(b ?? "");

export function applyCorrections<T extends { id: string; fieldValues: Values }>(
  entries: T[],
  corrections: Correction[],
): Corrected<T>[] {
  const byEntry = new Map(corrections.map((c) => [c.id, c]));
  return entries.map((entry) => {
    const correction = byEntry.get(entry.id) ?? null;
    const corrected: string[] = [];
    const fieldValues: Values = { ...entry.fieldValues };
    for (const [code, value] of Object.entries(correction?.fields ?? {})) {
      if (sameValue(entry.fieldValues[code], value)) continue;
      fieldValues[code] = value;
      corrected.push(code);
    }
    return {
      ...entry,
      fieldValues,
      rawValues: entry.fieldValues,
      corrected,
      correction,
    };
  });
}
