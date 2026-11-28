export interface PitAssignee {
  name: string;
  uid: string | null;
}

export interface PitShift {
  id: string;
  label: string;
  kind: string;
  assignees: PitAssignee[];
  startMatch: number | null;
  endMatch: number | null;
  startsAt: Date | null;
  endsAt: Date | null;
}

export interface PitSchedule {
  shifts: PitShift[];
  syncedAt: Date | null;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : "");
const int = (v: unknown) =>
  typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : null;
const date = (v: unknown): Date | null => {
  const d = new Date(str(v));
  return str(v) === "" || Number.isNaN(d.getTime()) ? null : d;
};

function parseShift(raw: Raw): PitShift {
  return {
    id: str(raw.id),
    label: str(raw.label),
    kind: str(raw.kind),
    assignees: (Array.isArray(raw.assignees) ? raw.assignees : [])
      .filter(isRecord)
      .map((a) => ({ name: str(a.name), uid: str(a.uid) || null })),
    startMatch: int(raw.startMatch),
    endMatch: int(raw.endMatch),
    startsAt: date(raw.startsAt),
    endsAt: date(raw.endsAt),
  };
}

export function parsePitSchedule(data: unknown): PitSchedule | null {
  if (!isRecord(data)) return null;
  return {
    shifts: (Array.isArray(data.shifts) ? data.shifts : [])
      .filter(isRecord)
      .map(parseShift),
    syncedAt: date(data.syncedAt),
  };
}

const clock = (d: Date) =>
  d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });

export function rangeText(shift: PitShift): string {
  const { startMatch: start, endMatch: end } = shift;
  if (start !== null) {
    return end === null || end === start ? `Q${start}` : `Q${start}-${end}`;
  }
  if (!shift.startsAt) return "";
  return shift.endsAt
    ? `${clock(shift.startsAt)} to ${clock(shift.endsAt)}`
    : clock(shift.startsAt);
}

export const includes = (shift: PitShift, uid: string) =>
  shift.assignees.some((a) => a.uid === uid);
