import { Timestamp } from "firebase/firestore";

export const roleKeys = ["start", "endgame", "auto", "teleop"] as const;
export type RoleKey = (typeof roleKeys)[number];

export type RobotRoles = Partial<Record<RoleKey, string>>;

export interface Brief {
  id: string;
  eventKey: string;
  matchId: string;
  robotPlans: Record<number, string>;
  robotRoles: Record<number, RobotRoles>;
  keyPoints: string;
  ready: boolean;
  authorUid: string;
  authorDisplayName: string;
  updatedMs: number;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : "");

export const briefId = (eventKey: string, matchId: string) =>
  `${eventKey}_${matchId}`;

export function matchIdOf(eventKey: string, matchKey: string): string {
  const prefix = `${eventKey}_`;
  return matchKey.startsWith(prefix) ? matchKey.slice(prefix.length) : matchKey;
}

export function emptyBrief(eventKey: string, matchId: string): Brief {
  return {
    id: briefId(eventKey, matchId),
    eventKey,
    matchId,
    robotPlans: {},
    robotRoles: {},
    keyPoints: "",
    ready: false,
    authorUid: "",
    authorDisplayName: "",
    updatedMs: 0,
  };
}

const teamOf = (key: string) => {
  const n = Number.parseInt(key, 10);
  return Number.isInteger(n) && String(n) === key.trim() ? n : null;
};

function parseRoles(raw: unknown): RobotRoles {
  if (!isRecord(raw)) return {};
  const out: RobotRoles = {};
  for (const role of roleKeys) {
    if (typeof raw[role] === "string") out[role] = raw[role];
  }
  return out;
}

export function parseBrief(id: string, data: Raw): Brief {
  const eventKey = str(data.eventKey);
  const matchId = str(data.matchId);
  const robotPlans: Record<number, string> = {};
  if (isRecord(data.robotPlans)) {
    for (const [key, value] of Object.entries(data.robotPlans)) {
      const team = teamOf(key);
      if (team !== null && typeof value === "string") robotPlans[team] = value;
    }
  }
  const robotRoles: Record<number, RobotRoles> = {};
  if (isRecord(data.robotRoles)) {
    for (const [key, value] of Object.entries(data.robotRoles)) {
      const team = teamOf(key);
      if (team !== null) robotRoles[team] = parseRoles(value);
    }
  }
  const parsed = Date.parse(str(data.updatedAt));
  return {
    id: id !== "" ? id : briefId(eventKey, matchId),
    eventKey,
    matchId,
    robotPlans,
    robotRoles,
    keyPoints: str(data.keyPoints),
    ready: data.ready === true,
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

const rolesEmpty = (roles: RobotRoles) =>
  roleKeys.every((role) => (roles[role] ?? "").trim() === "");

export function isEmptyBrief(brief: Brief): boolean {
  return (
    brief.keyPoints.trim() === "" &&
    Object.values(brief.robotPlans).every((p) => p.trim() === "") &&
    Object.values(brief.robotRoles).every(rolesEmpty)
  );
}

export interface Edit {
  robotPlans?: Record<number, string>;
  robotRoles?: Record<number, RobotRoles>;
  ready?: boolean;
}

export interface Author {
  uid: string;
  displayName: string;
}

export function applyEdit(
  prev: Brief,
  edit: Edit,
  author: Author,
  nowMs: number,
): Brief {
  return {
    ...prev,
    robotPlans: edit.robotPlans ?? prev.robotPlans,
    robotRoles: edit.robotRoles ?? prev.robotRoles,
    ready: edit.ready ?? prev.ready,
    authorUid: author.uid,
    authorDisplayName: author.displayName.slice(0, 128),
    updatedMs: Math.max(nowMs, prev.updatedMs),
  };
}

export function briefDoc(brief: Brief): Raw {
  const robotPlans: Record<string, string> = {};
  for (const [team, plan] of Object.entries(brief.robotPlans)) {
    if (plan.trim() !== "") robotPlans[team] = plan;
  }
  const robotRoles: Record<string, Raw> = {};
  for (const [team, roles] of Object.entries(brief.robotRoles)) {
    if (rolesEmpty(roles)) continue;
    const answers: Raw = {};
    for (const role of roleKeys) {
      const answer = (roles[role] ?? "").trim();
      if (answer !== "") answers[role] = answer;
    }
    robotRoles[team] = answers;
  }
  return {
    id: brief.id,
    eventKey: brief.eventKey,
    matchId: brief.matchId,
    robotPlans,
    ...(Object.keys(robotRoles).length > 0 ? { robotRoles } : {}),
    keyPoints: brief.keyPoints,
    ready: brief.ready,
    authorUid: brief.authorUid,
    authorDisplayName: brief.authorDisplayName,
    updatedAt: new Date(brief.updatedMs).toISOString(),
    updatedAtTs: Timestamp.fromMillis(brief.updatedMs),
  };
}
