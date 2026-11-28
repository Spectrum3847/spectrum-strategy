import type { TrexReport } from "../data/parse";
import { traitLabel, traits } from "./traits";

export const inEvent = (r: TrexReport, eventKey: string) =>
  eventKey === "" || r.eventKey === "" || r.eventKey === eventKey;

export function eventNameFor(reports: TrexReport[], eventKey: string): string {
  if (eventKey === "") return "";
  const used = reports.find(
    (r) => r.eventKey === eventKey && r.eventName !== "",
  );
  return used?.eventName ?? eventKey;
}

export interface TraitGroup {
  key: string;
  label: string;
  reports: TrexReport[];
}

export interface TeamGroup {
  team: number;
  count: number;
  traits: TraitGroup[];
}

const newestFirst = (a: TrexReport, b: TrexReport) =>
  b.updatedAt.localeCompare(a.updatedAt);

export interface ReportFilter {
  eventKey: string;
  thisEventOnly: boolean;
  trait: string;
  search: string;
}

export function groupReports(
  reports: TrexReport[],
  filter: ReportFilter,
): TeamGroup[] {
  const byTeam = new Map<number, TrexReport[]>();
  for (const r of reports) {
    if (filter.thisEventOnly && !inEvent(r, filter.eventKey)) continue;
    if (filter.trait !== "" && r.trait !== filter.trait) continue;
    if (filter.search !== "" && !String(r.teamNumber).includes(filter.search)) {
      continue;
    }
    const list = byTeam.get(r.teamNumber) ?? [];
    list.push(r);
    byTeam.set(r.teamNumber, list);
  }
  const known = traits.map((t) => t.key);
  return [...byTeam.entries()]
    .sort(([a], [b]) => a - b)
    .map(([team, list]) => {
      const keys = [
        ...known,
        ...[...new Set(list.map((r) => r.trait))]
          .filter((k) => !known.includes(k))
          .sort(),
      ];
      return {
        team,
        count: list.length,
        traits: keys
          .map((key) => ({
            key,
            label: traitLabel(key),
            reports: list.filter((r) => r.trait === key).sort(newestFirst),
          }))
          .filter((g) => g.reports.length > 0),
      };
    });
}
