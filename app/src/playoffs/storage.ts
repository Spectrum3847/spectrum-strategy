import { emptyBoard, type PlayoffBoard, parseBoard } from "./board";

export interface Cached {
  board: PlayoffBoard;
  ms: number;
  by: string;
  pending: boolean;
}

export const cacheKey = (eventKey: string) => `ss.playoff.cache.${eventKey}`;

export const legacyKey = (eventKey: string) => `ss.playoff.${eventKey}`;

type Raw = Record<string, unknown>;

export function loadCache(eventKey: string): Cached | null {
  if (eventKey === "") return null;
  try {
    const raw = localStorage.getItem(cacheKey(eventKey));
    if (raw === null) return null;
    const data = JSON.parse(raw) as Raw;
    return {
      board: parseBoard(data.board),
      ms: typeof data.ms === "number" ? data.ms : 0,
      by: typeof data.by === "string" ? data.by : "",
      pending: data.pending === true,
    };
  } catch {
    return null;
  }
}

export function saveCache(eventKey: string, cached: Cached): boolean {
  if (eventKey === "") return false;
  try {
    localStorage.setItem(cacheKey(eventKey), JSON.stringify(cached));
    return true;
  } catch {
    return false;
  }
}

export function loadLegacy(eventKey: string): PlayoffBoard | null {
  if (eventKey === "") return null;
  try {
    const raw = localStorage.getItem(legacyKey(eventKey));
    return raw === null ? null : parseBoard(JSON.parse(raw));
  } catch {
    return null;
  }
}

export function clearLegacy(eventKey: string) {
  try {
    localStorage.removeItem(legacyKey(eventKey));
  } catch {
  }
}

export const blankCache = (): Cached => ({
  board: emptyBoard(),
  ms: 0,
  by: "",
  pending: false,
});
