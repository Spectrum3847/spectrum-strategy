import { Timestamp } from "firebase/firestore";
import {
  boardVersion,
  emptyBoard,
  type PlayoffBoard,
  parseBoard,
} from "./board";

type Raw = Record<string, unknown>;

export const boardPath = (eventKey: string) => `playoffBoards/${eventKey}`;

export interface Shared {
  board: PlayoffBoard;
  ms: number;
  by: string;
}

export function parseShared(data: Raw): Shared {
  const parsed = Date.parse(
    typeof data.updatedAt === "string" ? data.updatedAt : "",
  );
  return {
    board: parseBoard(data),
    ms:
      data.updatedAtTs instanceof Timestamp
        ? data.updatedAtTs.toMillis()
        : Number.isNaN(parsed)
          ? 0
          : parsed,
    by: typeof data.updatedBy === "string" ? data.updatedBy : "",
  };
}

export const nextStamp = (nowMs: number, ...seenMs: number[]) =>
  Math.max(nowMs, ...seenMs);

export function boardDoc(
  eventKey: string,
  board: PlayoffBoard,
  ms: number,
  by: string,
): Raw {
  return {
    eventKey,
    version: boardVersion,
    labels: board.labels,
    meeting: board.meeting,
    styles: board.styles,
    alliance: board.alliance,
    updatedAt: new Date(ms).toISOString(),
    updatedAtTs: Timestamp.fromMillis(ms),
    updatedBy: by.slice(0, 128),
  };
}

export function takesRemote(input: {
  heldMs: number;
  remoteMs: number;
  unsent: boolean;
}): boolean {
  return input.remoteMs > input.heldMs && !input.unsent;
}

export const sameBoard = (a: PlayoffBoard, b: PlayoffBoard) =>
  JSON.stringify(a) === JSON.stringify(b);

export const isBlank = (board: PlayoffBoard) => sameBoard(board, emptyBoard());
