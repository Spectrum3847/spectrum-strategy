import { matchLabel } from "../data/matchKey";
import { allFields, type ScoutConfig } from "./config";

export interface AccuracyAlert {
  entryId: string;
  teamNumber: number;
  tbaMatchKey: string;
  fieldCodes: string[];
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);

export function parseAlert(id: string, data: Raw): AccuracyAlert {
  const flagged = Array.isArray(data.flaggedFields) ? data.flaggedFields : [];
  const team = Number(data.teamNumber);
  return {
    entryId: id,
    teamNumber: Number.isFinite(team) ? Math.trunc(team) : 0,
    tbaMatchKey: typeof data.tbaMatchKey === "string" ? data.tbaMatchKey : "",
    fieldCodes: flagged.flatMap((f) =>
      isRecord(f) && typeof f.fieldCode === "string" ? [f.fieldCode] : [],
    ),
  };
}

export const alertsHeading = (count: number) =>
  `${count === 1 ? "1 entry" : `${count} entries`} may have inaccurate data. Please review and re-scout if needed.`;

export function alertLine(alert: AccuracyAlert, config: ScoutConfig): string {
  const titles = new Map(
    allFields(config).map((f) => [f.code, f.title.trim() || f.code]),
  );
  const fields = alert.fieldCodes.map((c) => titles.get(c) ?? c).join(", ");
  const match = alert.tbaMatchKey ? matchLabel(alert.tbaMatchKey) : "";
  const where = [`Team ${alert.teamNumber}`, match].filter(Boolean).join(", ");
  return fields ? `${where}: ${fields}` : where;
}
