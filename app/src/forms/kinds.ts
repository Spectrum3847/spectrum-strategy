import type { FormKind } from "../data/formConfig";

export type { FormKind };

export const entryCollection: Record<FormKind, string> = {
  pit: "pitScoutEntries",
  prescout: "prescoutEntries",
};

export function parseTeamParam(raw: string | undefined): number | null {
  if (raw === undefined || !/^\d{1,5}$/.test(raw)) return null;
  const n = Number(raw);
  return n >= 1 ? n : null;
}
