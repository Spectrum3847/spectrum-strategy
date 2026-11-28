import { Timestamp } from "firebase/firestore";

export const sectionKeys = ["auto", "teleop", "endgame", "notes"] as const;
export type SectionKey = (typeof sectionKeys)[number];

export const sectionLabels: Record<SectionKey, string> = {
  auto: "Auto",
  teleop: "Teleop",
  endgame: "Endgame",
  notes: "Notes",
};

export const sectionHints: Record<SectionKey, string> = {
  auto: "What happened in auto, in your own words.",
  teleop: "What happened in teleop, in your own words.",
  endgame: "What happened in endgame, in your own words.",
  notes:
    "Anything that does not fit one phase: penalties, breakdowns, what to watch for next time.",
};

export const maxSection = 4000;

export type Sections = Record<SectionKey, string>;

export interface PostMatchReport extends Sections {
  id: string;
  eventKey: string;
  matchId: string;
  authorUid: string;
  authorDisplayName: string;
  updatedMs: number;
}

type Raw = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" ? v : "");

export const reportId = (eventKey: string, matchId: string) =>
  `${eventKey}_${matchId}`;

export function emptyReport(
  eventKey: string,
  matchId: string,
): PostMatchReport {
  return {
    id: reportId(eventKey, matchId),
    eventKey,
    matchId,
    auto: "",
    teleop: "",
    endgame: "",
    notes: "",
    authorUid: "",
    authorDisplayName: "",
    updatedMs: 0,
  };
}

export function parseReport(id: string, data: Raw): PostMatchReport {
  const eventKey = str(data.eventKey);
  const matchId = str(data.matchId);
  const parsed = Date.parse(str(data.updatedAt));
  return {
    id: id !== "" ? id : reportId(eventKey, matchId),
    eventKey,
    matchId,
    auto: str(data.auto),
    teleop: str(data.teleop),
    endgame: str(data.endgame),
    notes: str(data.notes),
    authorUid: str(data.authorUid),
    authorDisplayName: str(data.authorDisplayName),
    updatedMs:
      data.updatedAtTs instanceof Timestamp
        ? data.updatedAtTs.toMillis()
        : Number.isNaN(parsed)
          ? 0
          : parsed,
  };
}

export const isEmptyReport = (report: Sections) =>
  sectionKeys.every((key) => report[key].trim() === "");

export interface Author {
  uid: string;
  displayName: string;
}

export function applySections(
  prev: PostMatchReport,
  sections: Sections,
  author: Author,
  nowMs: number,
): PostMatchReport {
  return {
    ...prev,
    auto: sections.auto,
    teleop: sections.teleop,
    endgame: sections.endgame,
    notes: sections.notes,
    authorUid: author.uid,
    authorDisplayName: author.displayName.slice(0, 128),
    updatedMs: Math.max(nowMs, prev.updatedMs),
  };
}

export function reportDoc(report: PostMatchReport): Raw {
  return {
    id: report.id,
    eventKey: report.eventKey,
    matchId: report.matchId,
    auto: report.auto,
    teleop: report.teleop,
    endgame: report.endgame,
    notes: report.notes,
    authorUid: report.authorUid,
    authorDisplayName: report.authorDisplayName,
    updatedAt: new Date(report.updatedMs).toISOString(),
    updatedAtTs: Timestamp.fromMillis(report.updatedMs),
  };
}
