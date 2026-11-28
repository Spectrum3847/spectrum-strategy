type Raw = Record<string, unknown>;

const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const text = (v: unknown) => (typeof v === "string" ? v : "");

export interface Column {
  key: string;
  name: string;
  items: string[];
}

function parseColumns(raw: unknown, itemsKey: "names" | "teams"): Column[] {
  if (!Array.isArray(raw)) return [];
  const out: Column[] = [];
  for (const entry of raw) {
    if (!isRecord(entry)) continue;
    const { key, name } = entry;
    if (typeof key !== "string" || key === "" || typeof name !== "string") {
      continue;
    }
    const list = entry[itemsKey];
    const items = Array.isArray(list)
      ? list.filter(
          (v): v is string => typeof v === "string" && v.trim() !== "",
        )
      : [];
    out.push({ key, name, items });
  }
  return out;
}

export interface Table {
  title: string;
  columns: Column[];
  authorUid: string;
  authorName: string;
  updatedAt: string;
}

function parseTable(data: Raw | null, itemsKey: "names" | "teams"): Table {
  return {
    title: text(data?.title),
    columns: parseColumns(data?.columns, itemsKey),
    authorUid: text(data?.authorUid),
    authorName: text(data?.authorDisplayName).trim(),
    updatedAt: text(data?.updatedAt),
  };
}

export const parseAssignments = (data: Raw | null) => parseTable(data, "names");
export const parseTeamList = (data: Raw | null) => parseTable(data, "teams");

export interface Section {
  name: string;
  scouters: string[];
  teams: string[];
  assignmentKey: string | null;
  teamKey: string | null;
}

const norm = (s: string) => s.trim().toLowerCase();

export function mergeSections(
  assignments: Column[],
  teamColumns: Column[],
): Section[] {
  const used = new Set<number>();
  const sections: Section[] = assignments.map((column) => {
    const at = teamColumns.findIndex(
      (t, i) => !used.has(i) && norm(t.name) === norm(column.name),
    );
    if (at !== -1) used.add(at);
    return {
      name: column.name,
      scouters: column.items,
      teams: at === -1 ? [] : (teamColumns[at]?.items ?? []),
      assignmentKey: column.key,
      teamKey: teamColumns[at]?.key ?? null,
    };
  });
  teamColumns.forEach((t, i) => {
    if (!used.has(i)) {
      sections.push({
        name: t.name,
        scouters: [],
        teams: t.items,
        assignmentKey: null,
        teamKey: t.key,
      });
    }
  });
  return sections;
}

export const isAssignedTo = (section: Section, name: string) =>
  name.trim() !== "" && section.scouters.some((s) => norm(s) === norm(name));

export const totalTeams = (columns: Column[]) =>
  columns.reduce((sum, c) => sum + c.items.length, 0);
