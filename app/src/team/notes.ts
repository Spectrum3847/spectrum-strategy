import type {
  EventEntry,
  PitEntry,
  PrescoutEntry,
  TrexReport,
} from "../data/parse";
import { noteId, type TeamNote } from "../data/teamNotes";
import type { ScoutConfig } from "../scout/config";
import { allNotes, commentsFor, type TeamComment } from "./format";

const newest = (a: { updatedAt: string }, b: { updatedAt: string }) =>
  b.updatedAt.localeCompare(a.updatedAt);

export function notesByTeam(input: {
  teams: number[];
  eventKey: string;
  config: ScoutConfig;
  entries: EventEntry[];
  pit: { config: ScoutConfig; entries: PitEntry[] };
  prescout: { config: ScoutConfig; entries: PrescoutEntry[] };
  trex: TrexReport[];
  notes: TeamNote[];
}): Map<number, TeamComment[]> {
  const out = new Map<number, TeamComment[]>();
  for (const team of input.teams) {
    out.set(
      team,
      allNotes({
        scout: commentsFor(
          input.config,
          input.entries.filter((e) => e.teamNumber === team),
        ),
        pit: {
          config: input.pit.config,
          entries: input.pit.entries
            .filter((e) => e.teamNumber === team)
            .sort(newest),
        },
        prescout: {
          config: input.prescout.config,
          entries: input.prescout.entries
            .filter((e) => e.teamNumber === team)
            .sort(newest),
        },
        trex: input.trex.filter(
          (r) =>
            r.teamNumber === team &&
            r.report.trim() !== "" &&
            (r.eventKey === "" || r.eventKey === input.eventKey),
        ),
        note:
          input.notes.find((n) => n.id === noteId(input.eventKey, team)) ??
          null,
      }),
    );
  }
  return out;
}
