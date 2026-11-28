import type { EventEntry, FormEntry, TrexReport } from "../data/parse";
import type { TeamNote } from "../data/teamNotes";
import {
  allFields,
  labelForStored,
  type ScoutConfig,
  type ScoutField,
  selectedKeys,
  type Values,
} from "../scout/config";
import { traitLabel } from "../trex/traits";

export const formatStat = (n: number) =>
  Number.isInteger(n) ? String(n) : n.toFixed(1);

export const percent = (successes: number, total: number) =>
  `${Math.round((successes / total) * 100)}%`;

export interface Answer {
  label: string;
  value: string;
}

export function displayValue(field: ScoutField, raw: unknown): string {
  switch (field.type) {
    case "select":
      return labelForStored(field, raw);
    case "checkboxSelect":
      return selectedKeys(raw)
        .map((key) => field.choices?.find(([k]) => k === key)?.[1] ?? key)
        .join(", ");
    case "boolean":
      return raw === true || raw === "true"
        ? "Yes"
        : raw === false || raw === "false"
          ? "No"
          : "";
    case "document":
      return String(raw ?? "").trim() === "" ? "" : "Attached";
    case "tbaTeamAndRobot":
      return "";
    default:
      return String(raw ?? "").trim();
  }
}

export function answersFor(
  config: ScoutConfig,
  values: Values,
  skip: ReadonlySet<string> = new Set(),
): Answer[] {
  const out: Answer[] = [];
  for (const field of allFields(config)) {
    if (skip.has(field.code)) continue;
    const value = displayValue(field, values[field.code]);
    if (value === "") continue;
    out.push({ label: field.title.trim() || field.code, value });
  }
  return out;
}

export type NoteSource = "Scout" | "T-REx" | "Prescout" | "Pit" | "Team note";

export interface TeamComment {
  id: string;
  source: NoteSource;
  text: string;
  fieldTitle: string;
  scoutName: string;
  updatedAt: string;
  matchKey: string | null;
  strokesByPhase?: Record<string, unknown>;
}

const nameField = /scouter|scout name|\bname\b|e-?mail/i;

export const isNameField = (f: ScoutField) =>
  nameField.test(`${f.title} ${f.code}`);

export const commentFields = (config: ScoutConfig): ScoutField[] =>
  allFields(config).filter(
    (f) => (f.type === "text" || f.type === "longText") && !isNameField(f),
  );

const newestFirst = (a: TeamComment, b: TeamComment) =>
  b.updatedAt.localeCompare(a.updatedAt);

export function commentsFor(
  config: ScoutConfig,
  entries: EventEntry[],
): TeamComment[] {
  const fields = commentFields(config);
  const out: TeamComment[] = [];
  for (const entry of entries) {
    let drawing = entry.strokesByPhase;
    for (const field of fields) {
      const raw = entry.fieldValues[field.code];
      const text = typeof raw === "string" ? raw.trim() : "";
      if (text === "") continue;
      out.push({
        id: `${entry.id}:${field.code}`,
        source: "Scout",
        text,
        fieldTitle: field.title.trim() || field.code,
        scoutName: entry.scoutName,
        updatedAt: entry.updatedAt,
        matchKey: entry.tbaMatchKey,
        ...(drawing && { strokesByPhase: drawing }),
      });
      drawing = undefined;
    }
  }
  return out.sort(newestFirst);
}

function recordNotes(
  source: NoteSource,
  config: ScoutConfig,
  entries: readonly FormEntry[],
): TeamComment[] {
  const fields = allFields(config).filter(
    (f) => f.type === "longText" || f.code === "comments",
  );
  return entries.flatMap((entry) =>
    fields.flatMap((field) => {
      const raw = entry.fieldValues[field.code];
      const text = typeof raw === "string" ? raw.trim() : "";
      return text === ""
        ? []
        : [
            {
              id: `${entry.id}:${field.code}`,
              source,
              text,
              fieldTitle: field.title.trim() || field.code,
              scoutName: entry.scoutName,
              updatedAt: entry.updatedAt,
              matchKey: null,
            },
          ];
    }),
  );
}

export function allNotes(input: {
  scout: TeamComment[];
  pit: { config: ScoutConfig; entries: readonly FormEntry[] };
  prescout: { config: ScoutConfig; entries: readonly FormEntry[] };
  trex: readonly TrexReport[];
  note: TeamNote | null;
}): TeamComment[] {
  const trex = input.trex.flatMap((r): TeamComment[] => {
    const text = r.report.trim();
    if (text === "") return [];
    const title = [
      traitLabel(r.trait),
      r.rating !== null && `rated ${r.rating} of 5`,
      r.matchNumber > 0 && `match ${r.matchNumber}`,
    ]
      .filter(Boolean)
      .join(", ");
    return [
      {
        id: `trex:${r.id}`,
        source: "T-REx",
        text,
        fieldTitle: title,
        scoutName: r.scoutName,
        updatedAt: r.updatedAt,
        matchKey: null,
      },
    ];
  });
  const note = input.note;
  const team: TeamComment[] =
    note && note.text.trim() !== ""
      ? [
          {
            id: `note:${note.id}`,
            source: "Team note",
            text: note.text.trim(),
            fieldTitle: "",
            scoutName: note.authorDisplayName,
            updatedAt: new Date(note.updatedMs).toISOString(),
            matchKey: null,
          },
        ]
      : [];
  return [
    ...input.scout,
    ...recordNotes("Pit", input.pit.config, input.pit.entries),
    ...recordNotes("Prescout", input.prescout.config, input.prescout.entries),
    ...trex,
    ...team,
  ].sort(newestFirst);
}
