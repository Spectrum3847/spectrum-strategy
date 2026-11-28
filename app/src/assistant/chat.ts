import { Timestamp } from "firebase/firestore";
import { formatStat } from "../team/format";
import type { TeamRow } from "../teams/rows";
import {
  type AssistantRequest,
  untrustedSentence,
  wrapUntrusted,
} from "./queue";

export type Role = "user" | "assistant";

export interface Turn {
  role: Role;
  content: string;
}

export interface Message {
  kind: "user" | "assistant" | "error";
  text: string;
  model?: string;
  at?: string;
}

export interface Session {
  id: string;
  title: string | null;
  createdAt: string;
  updatedAt: string;
  messages: Message[];
  turns: Turn[];
}

export const maxEntries = 200;
export const maxChatChars = 300_000;
export const maxQuestionChars = 1000;
export const historyCharBudget = 3000;
export const historyTurnChars = 1200;
export const groundingCharBudget = 6000;
export const topTeams = 10;
export const maxMentioned = 4;
export const commentsPerTeam = 4;
export const commentChars = 200;
export const chatMinimumChars = 10;

export const chatSystem = (team: number) =>
  `You are the FRC strategy assistant for team ${team}, answering a strategy lead's questions between matches. Answer only from the event data in the message. Never invent a team number, an EPA or a match result. When the data does not say, begin with "Not in the data:" and say what to check next. Never begin an answer with "I cannot", "I can't", "I'm sorry" or "As an AI". Keep answers short: the lead is reading between matches. EPA is expected points added from Statbotics. Scouted values are interquartile means of points per match from our own scouts. ${untrustedSentence}`;

export const chatKey = (
  uid: string,
  conversation: string,
  turn: number,
  token: string,
) => `ai-chat:${uid}:${conversation}:${turn}:${token}`;

export function trimHistory(
  turns: Turn[],
  maxChars = historyCharBudget,
): Turn[] {
  let kept = turns;
  let total = kept.reduce((sum, t) => sum + t.content.length, 0);
  while (total > maxChars && kept.length > 2) {
    total -= (kept[0]?.content.length ?? 0) + (kept[1]?.content.length ?? 0);
    kept = kept.slice(2);
  }
  return kept;
}

const oneLine = (text: string) => text.replace(/\s+/g, " ").trim();
const clip = (text: string, max: number) =>
  text.length <= max ? text : `${text.slice(0, max - 3)}...`;

export interface NextMatch {
  label: string;
  alliance: string;
  ours: number[];
  opponents: number[];
}

export interface Facts {
  eventKey: string;
  team: number;
  rows: TeamRow[];
  next: NextMatch | null;
  commentsOf(team: number): string[];
}

export function mentioned(text: string, rows: TeamRow[]): number[] {
  const known = new Set(rows.map((r) => r.team));
  const found: number[] = [];
  for (const m of text.matchAll(/\b\d{1,5}\b/g)) {
    const n = Number(m[0]);
    if (known.has(n) && !found.includes(n)) found.push(n);
  }
  return found;
}

function teamLine(row: TeamRow): string {
  const parts = [
    row.rank !== null &&
      `rank ${row.rank}${row.record !== "" ? ` (${row.record})` : ""}`,
    row.epa !== null && `EPA ${formatStat(row.epa)}`,
    row.matches > 0
      ? `scouted ${row.matches} ${row.matches === 1 ? "match" : "matches"}`
      : "not scouted yet",
    row.iqm.total !== null && `total ${formatStat(row.iqm.total)}`,
    row.iqm.auto !== null && `auto ${formatStat(row.iqm.auto)}`,
    row.iqm.teleop !== null && `teleop ${formatStat(row.iqm.teleop)}`,
    row.sd !== null && `spread ${formatStat(row.sd)}`,
    row.form !== null &&
      `form ${row.form > 0 ? "+" : ""}${formatStat(row.form)} (last matches against earlier)`,
    row.climb > 0 && `best climb L${row.climb}`,
  ].filter((p): p is string => p !== false);
  const name = row.nickname === "" ? "" : ` ${oneLine(row.nickname)}`;
  return `- team ${row.team}${name}: ${parts.join(", ")}`;
}

const byStrength = (a: TeamRow, b: TeamRow) =>
  (b.epa ?? -1) - (a.epa ?? -1) ||
  (a.rank ?? Infinity) - (b.rank ?? Infinity) ||
  a.team - b.team;

export function grounding(
  facts: Facts,
  asked: number[],
  budget = groundingCharBudget,
): string {
  const { rows, next } = facts;
  const lines = [
    `Event ${facts.eventKey}, our team is ${facts.team}. ${rows.length} teams, ${rows.filter((r) => r.matches > 0).length} scouted.`,
  ];
  if (next) {
    lines.push(
      `Our next match: ${next.label}, ${next.alliance} alliance, ${next.ours.join(", ")} against ${next.opponents.join(", ")}.`,
    );
  }
  const byTeam = new Map(rows.map((r) => [r.team, r]));
  const named = asked
    .slice(0, maxMentioned)
    .flatMap((t) => byTeam.get(t) ?? []);
  const rest = [...rows]
    .sort(byStrength)
    .filter((r) => !named.includes(r))
    .slice(0, named.length > 0 ? 3 : topTeams);
  const sections: string[][] = [];
  if (named.length > 0) {
    sections.push(["Teams asked about:", ...named.map(teamLine)]);
    for (const row of named) {
      const notes = facts.commentsOf(row.team).slice(0, commentsPerTeam);
      if (notes.length > 0) {
        sections.push([
          `Scout comments on team ${row.team}:`,
          ...notes.map((n) => `- ${clip(oneLine(n), commentChars)}`),
        ]);
      }
    }
  }
  sections.push([
    named.length > 0 ? "Other strong teams:" : "Strongest teams by EPA:",
    ...rest.map(teamLine),
  ]);
  let size = lines.join("\n").length;
  for (const section of sections) {
    const text = section.join("\n");
    if (size + text.length + 1 > budget) {
      for (const line of section) {
        if (size + line.length + 1 > budget) break;
        lines.push(line);
        size += line.length + 1;
      }
      break;
    }
    lines.push(...section);
    size += text.length + 1;
  }
  return lines.join("\n");
}

const speaker = (t: Turn) => (t.role === "user" ? "Lead" : "Assistant");

export function chatRequest(
  facts: Facts,
  history: Turn[],
  question: string,
  cacheKey: string,
): AssistantRequest {
  const text = question.trim().slice(0, maxQuestionChars);
  const lastAsked = [...history].reverse().find((t) => t.role === "user");
  const asked = mentioned(text, facts.rows);
  const names =
    asked.length > 0 || !lastAsked
      ? asked
      : mentioned(lastAsked.content, facts.rows);
  const past = trimHistory(
    history.map((t) => ({ ...t, content: clip(t.content, historyTurnChars) })),
  );
  const data = [
    grounding(facts, names),
    ...(past.length > 0
      ? [
          "",
          "Conversation so far:",
          ...past.map((t) => `${speaker(t)}: ${oneLine(t.content)}`),
        ]
      : []),
  ].join("\n");
  return {
    cacheKey,
    system: chatSystem(facts.team),
    prompt: [
      "Event data and the conversation so far:",
      wrapUntrusted(data),
      "",
      `Question from the lead: ${oneLine(text)}`,
      "",
    ].join("\n"),
    minimumChars: chatMinimumChars,
  };
}

export const newSession = (id: string, now: Date): Session => ({
  id,
  title: null,
  createdAt: now.toISOString(),
  updatedAt: now.toISOString(),
  messages: [],
  turns: [],
});

export const displayTitle = (s: Session) => s.title ?? "New chat";

function titleOf(question: string): string | null {
  const first = question.trim().split("\n")[0]?.trim() ?? "";
  if (first === "") return null;
  return first.length <= 60 ? first : `${first.slice(0, 57)}...`;
}

function capped<T>(list: T[], text: (item: T) => string): T[] {
  const sizes = list.map((item) => text(item).length);
  let chars = sizes.reduce((sum, n) => sum + n, 0);
  let drop = 0;
  while (
    list.length - drop > 2 &&
    (list.length - drop > maxEntries || chars > maxChatChars)
  ) {
    chars -= (sizes[drop] ?? 0) + (sizes[drop + 1] ?? 0);
    drop += 2;
  }
  return list.slice(drop);
}

export function withExchange(
  session: Session,
  question: string,
  answer: { text: string; model: string },
  now: Date,
): Session {
  const asked = question.trim().slice(0, maxQuestionChars);
  const at = now.toISOString();
  return {
    ...session,
    title: session.title ?? titleOf(asked),
    updatedAt: at,
    messages: capped(
      [
        ...session.messages,
        { kind: "user", text: asked },
        { kind: "assistant", text: answer.text, model: answer.model, at },
      ],
      (m) => m.text,
    ),
    turns: capped(
      [
        ...session.turns,
        { role: "user", content: asked },
        { role: "assistant", content: answer.text },
      ],
      (t) => t.content,
    ),
  };
}

export function sessionDoc(session: Session, uid: string, now: Date) {
  const stored = Date.parse(session.updatedAt);
  const stamp = Math.max(now.getTime(), Number.isNaN(stored) ? 0 : stored);
  return {
    id: session.id,
    ...(session.title !== null && { title: session.title }),
    messages: session.messages.map((m) => ({
      kind: m.kind,
      text: m.text,
      ...(m.kind === "assistant" && { source: "local" }),
      ...(m.model !== undefined && { model: m.model }),
      ...(m.at !== undefined && { at: m.at }),
    })),
    turns: session.turns.map((t) => ({ role: t.role, content: t.content })),
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    updatedAtTs: Timestamp.fromMillis(stamp),
    authorUid: uid,
  };
}

const text = (v: unknown) => (typeof v === "string" ? v : "");

export function parseSession(raw: unknown): Session | null {
  if (typeof raw !== "object" || raw === null) return null;
  const d = raw as Record<string, unknown>;
  const id = text(d.id);
  const createdAt = text(d.createdAt);
  const updatedAt = text(d.updatedAt);
  if (id === "" || Number.isNaN(Date.parse(updatedAt))) return null;
  const list = (v: unknown): Record<string, unknown>[] =>
    Array.isArray(v)
      ? v.filter(
          (x): x is Record<string, unknown> =>
            typeof x === "object" && x !== null,
        )
      : [];
  return {
    id,
    title: text(d.title) === "" ? null : text(d.title),
    createdAt: Number.isNaN(Date.parse(createdAt)) ? updatedAt : createdAt,
    updatedAt,
    messages: list(d.messages).map((m): Message => {
      const kind =
        m.kind === "user" || m.kind === "error" ? m.kind : "assistant";
      return {
        kind,
        text: text(m.text),
        ...(text(m.model) !== "" && { model: text(m.model) }),
        ...(!Number.isNaN(Date.parse(text(m.at))) && { at: text(m.at) }),
      };
    }),
    turns: list(d.turns).map((t) => ({
      role: t.role === "assistant" ? "assistant" : "user",
      content: text(t.content),
    })),
  };
}

export function mergeSessions(a: Session[], b: Session[]): Session[] {
  const byId = new Map<string, Session>();
  for (const s of [...a, ...b]) {
    const held = byId.get(s.id);
    if (!held || Date.parse(s.updatedAt) > Date.parse(held.updatedAt)) {
      byId.set(s.id, s);
    }
  }
  return [...byId.values()].sort(
    (x, y) => Date.parse(y.updatedAt) - Date.parse(x.updatedAt),
  );
}
