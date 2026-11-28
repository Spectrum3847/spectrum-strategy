import { groupByMatch, type StatInput } from "./stats";

export const windowOptions: { last: number | null; label: string }[] = [
  { last: null, label: "All" },
  { last: 6, label: "Last 6" },
  { last: 3, label: "Last 3" },
];

export function lastMatches(inputs: StatInput[], last: number | null) {
  if (last === null) return inputs;
  const groups = groupByMatch(inputs);
  if (groups.length <= last) return inputs;
  const keep = new Set(groups.slice(-last).map((g) => g.key));
  return inputs.filter((i) => keep.has(i.matchKey));
}

export function windowNote(last: number | null, total: number): string {
  if (total === 0) return "";
  if (last === null || total <= last) {
    return `Showing all ${total} scouted ${total === 1 ? "match" : "matches"}.`;
  }
  return `Showing the last ${last} of ${total} scouted matches. Stats, trend, summary and counts use only these.`;
}
