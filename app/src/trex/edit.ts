import { Timestamp } from "firebase/firestore";
import { type Column, type Table, totalTeams } from "./assignments";

export type Kind = "assignments" | "teamList";

export const tablePath = {
  assignments: "appConfig/trexAssignments",
  teamList: "appConfig/trexTeamList",
} as const;

const clean = (s: string) => s.trim();

const mapColumn = (
  columns: Column[],
  key: string,
  change: (column: Column) => Column,
) => columns.map((c) => (c.key === key ? change(c) : c));

function moved<T>(list: T[], index: number, delta: -1 | 1): T[] {
  const to = index + delta;
  const item = list[index];
  if (item === undefined || to < 0 || to >= list.length) return list;
  const next = [...list];
  next.splice(index, 1);
  next.splice(to, 0, item);
  return next;
}

export function addColumn(columns: Column[], key: string, name: string) {
  const trimmed = clean(name);
  if (trimmed === "") return columns;
  return [...columns, { key, name: trimmed, items: [] }];
}

export function renameColumn(columns: Column[], key: string, name: string) {
  const trimmed = clean(name);
  if (trimmed === "") return columns;
  return mapColumn(columns, key, (c) => ({ ...c, name: trimmed }));
}

export const removeColumn = (columns: Column[], key: string) =>
  columns.filter((c) => c.key !== key);

export function moveColumn(columns: Column[], key: string, delta: -1 | 1) {
  return moved(
    columns,
    columns.findIndex((c) => c.key === key),
    delta,
  );
}

export function addItem(columns: Column[], key: string, item: string) {
  const trimmed = clean(item);
  if (trimmed === "") return columns;
  return mapColumn(columns, key, (c) => ({
    ...c,
    items: [...c.items, trimmed],
  }));
}

export function addItems(columns: Column[], key: string, incoming: string[]) {
  return mapColumn(columns, key, (c) => {
    const seen = new Set(c.items.map((i) => i.toLowerCase()));
    const items = [...c.items];
    for (const raw of incoming) {
      const item = clean(raw);
      if (item !== "" && !seen.has(item.toLowerCase())) {
        seen.add(item.toLowerCase());
        items.push(item);
      }
    }
    return { ...c, items };
  });
}

export function renameItem(
  columns: Column[],
  key: string,
  index: number,
  item: string,
) {
  const trimmed = clean(item);
  if (trimmed === "") return columns;
  return mapColumn(columns, key, (c) => ({
    ...c,
    items: c.items.map((old, i) => (i === index ? trimmed : old)),
  }));
}

export const removeItem = (columns: Column[], key: string, index: number) =>
  mapColumn(columns, key, (c) => ({
    ...c,
    items: c.items.filter((_, i) => i !== index),
  }));

export const moveItem = (
  columns: Column[],
  key: string,
  index: number,
  delta: -1 | 1,
) =>
  mapColumn(columns, key, (c) => ({
    ...c,
    items: moved(c.items, index, delta),
  }));

export function parsePasted(raw: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const part of raw.split(/[\n\r,;\t]+/)) {
    const item = clean(part);
    if (item !== "" && !seen.has(item.toLowerCase())) {
      seen.add(item.toLowerCase());
      out.push(item);
    }
  }
  return out;
}

export interface Author {
  uid: string;
  displayName: string;
}

export const withColumns = (
  table: Table,
  columns: Column[],
  author: Author,
  now: Date,
): Table => ({
  ...table,
  columns,
  authorUid: author.uid,
  authorName: author.displayName,
  updatedAt: now.toISOString(),
});

export function toDoc(kind: Kind, table: Table): Record<string, unknown> {
  const itemsKey = kind === "teamList" ? "teams" : "names";
  return {
    ...(kind === "teamList" ? { title: table.title } : {}),
    columns: table.columns.map((c) => ({
      key: c.key,
      name: c.name,
      [itemsKey]: c.items,
    })),
    authorUid: table.authorUid,
    authorDisplayName: table.authorName,
    updatedAt: table.updatedAt,
    updatedAtTs: Timestamp.fromDate(new Date(table.updatedAt)),
  };
}

function textBlock(columns: Column[], empty: string) {
  return columns
    .map((c) =>
      [
        "",
        c.name,
        "-".repeat(c.name.length),
        ...(c.items.length === 0 ? [empty] : c.items),
      ].join("\n"),
    )
    .join("\n");
}

export function exportText(assignments: Table, teamList: Table): string {
  const names =
    assignments.columns.length === 0
      ? "T-Rex assignments\n(no traits added yet)"
      : `T-Rex assignments\n${textBlock(assignments.columns, "(unassigned)")}`;
  const title = teamList.title.trim() || "Team assignments";
  const teams =
    teamList.columns.length === 0
      ? `${title}\n(no columns added yet)`
      : `${title}\n${textBlock(teamList.columns, "(no teams yet)")}\n\nTotal teams: ${totalTeams(teamList.columns)}`;
  return `${names.trimEnd()}\n\n${teams.trimEnd()}`;
}
