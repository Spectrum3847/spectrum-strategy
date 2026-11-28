import { Timestamp } from "firebase/firestore";

export interface TeamNote {
  id: string;
  eventKey: string;
  teamNumber: number;
  text: string;
  authorUid: string;
  authorDisplayName: string;
  updatedMs: number;
}

type Raw = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" ? v : "");

export const noteId = (eventKey: string, team: number) => `${eventKey}_${team}`;

export function parseTeamNote(id: string, data: Raw): TeamNote {
  const parsed = Date.parse(str(data.updatedAt));
  return {
    id,
    eventKey: str(data.eventKey),
    teamNumber: typeof data.teamNumber === "number" ? data.teamNumber : 0,
    text: str(data.text),
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
