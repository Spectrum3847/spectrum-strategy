import { matchPath } from "../data/matchKey";
import type { LocalBoard } from "./local";
import { newSession, parseSession, type Session } from "./model";

export function boardTitle(s: Session): string {
  const name = s.eventName.trim();
  return name === ""
    ? `Match ${s.matchNumber}`
    : `${name} - Match ${s.matchNumber}`;
}

export function boardInScope(input: {
  selectedEventKey: string;
  boardEventKey: string;
  thisEventOnly: boolean;
}): boolean {
  if (!input.thisEventOnly || input.selectedEventKey === "") return true;
  if (input.boardEventKey === "") return true;
  return input.boardEventKey === input.selectedEventKey;
}

export interface ScopedBoards {
  mine: Session[];
  team: Session[];
  hidden: number;
}

const newestFirst = (a: Session, b: Session) => b.updatedMs - a.updatedMs;

export function scopeBoards(input: {
  local: Session[];
  remote: Session[];
  selectedEventKey: string;
  thisEventOnly: boolean;
}): ScopedBoards {
  const inScope = (s: Session) =>
    boardInScope({
      selectedEventKey: input.selectedEventKey,
      boardEventKey: s.eventKey,
      thisEventOnly: input.thisEventOnly,
    });
  const localIds = new Set(input.local.map((s) => s.id));
  const mine = input.local.filter(inScope).sort(newestFirst);
  const remoteOnly = input.remote.filter((s) => !localIds.has(s.id));
  const team = remoteOnly.filter(inScope).sort(newestFirst);
  return {
    mine,
    team,
    hidden:
      input.local.length - mine.length + (remoteOnly.length - team.length),
  };
}

export function localSessions(
  boards: LocalBoard[],
  fallbackField: string,
): { session: Session; key: string }[] {
  const byId = new Map<string, { session: Session; key: string }>();
  for (const { key, record } of boards) {
    const session = parseSession(
      String(record.doc.id ?? ""),
      record.doc,
      fallbackField,
    );
    if (session.id === "") continue;
    const held = byId.get(session.id);
    if (!held || session.updatedMs > held.session.updatedMs) {
      byId.set(session.id, { session, key });
    }
  }
  return [...byId.values()];
}

export interface PracticeInput {
  matchNumber: number;
  alliance: "Red" | "Blue";
  name: string;
  teams: number[];
  opponents: number[];
  eventKey: string;
  fieldId: string;
  author: { uid: string; displayName: string };
  id: string;
  nowMs: number;
}

export const maxPracticeTeams = 6;

export function practiceBoard(input: PracticeInput): Session {
  return {
    ...newSession({
      id: input.id,
      eventKey: input.eventKey,
      matchNumber: input.matchNumber,
      alliance: input.alliance,
      teamNumbers: [...input.teams, ...input.opponents],
      opponentTeams: input.opponents,
      fieldId: input.fieldId,
      author: input.author,
      nowMs: input.nowMs,
    }),
    eventName: input.name.trim(),
  };
}

export function isPracticeBoard(input: {
  session: Session;
  scheduled: boolean;
  scheduleKnown: boolean;
}): boolean {
  if (input.scheduled) return false;
  return input.scheduleKnown || input.session.opponentTeams.length > 0;
}

export function parseTeamList(text: string): {
  teams: number[];
  bad: string[];
} {
  const teams: number[] = [];
  const bad: string[] = [];
  for (const part of text.split(/[\s,]+/)) {
    if (part === "") continue;
    const m = /^(?:frc)?(\d{1,5})$/i.exec(part);
    const n = m ? Number(m[1]) : 0;
    if (n > 0) {
      if (!teams.includes(n)) teams.push(n);
    } else bad.push(part);
  }
  return { teams: teams.slice(0, maxPracticeTeams), bad };
}

export const sharedTeams = (ours: number[], opponents: number[]) =>
  ours.filter((n) => opponents.includes(n));

export function scheduledClash(
  eventKey: string,
  matchNumber: number,
  matchKeys: string[],
): string | null {
  if (eventKey === "") return null;
  const key = `${eventKey}_qm${matchNumber}`.toLowerCase();
  const found = matchKeys.find((k) => k.toLowerCase() === key);
  return found === undefined ? null : matchPath(found);
}
