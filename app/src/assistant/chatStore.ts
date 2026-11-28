import { parseSession, type Session } from "./chat";

const maxKept = 50;
const chatsKey = (uid: string) => `ss.ai.chats.${uid}`;
const deletedKey = (uid: string) => `ss.ai.chats.deleted.${uid}`;

function read(key: string): unknown {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? null : JSON.parse(raw);
  } catch {
    return null;
  }
}

function write(key: string, value: unknown): boolean {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    return false;
  }
}

export function loadChats(uid: string): Session[] {
  const raw = read(chatsKey(uid));
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((r) => parseSession(r) ?? []);
}

export function saveChats(uid: string, sessions: Session[]) {
  for (let n = Math.min(sessions.length, maxKept); n > 0; n >>= 1)
    if (write(chatsKey(uid), sessions.slice(0, n))) return;
}

export function loadDeleted(uid: string): string[] {
  const raw = read(deletedKey(uid));
  return Array.isArray(raw)
    ? raw.filter((x): x is string => typeof x === "string")
    : [];
}

export function saveDeleted(uid: string, ids: string[]) {
  write(deletedKey(uid), ids.slice(-200));
}
