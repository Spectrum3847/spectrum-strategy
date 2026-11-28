import type { EventEntry } from "../data/parse";
import { allFields, type ScoutConfig } from "../scout/config";
import {
  computeStats,
  entryMatchKey,
  phaseStats,
  type RateRow,
} from "../team/stats";
import { csvLine } from "./csv";

const climbField = /climb/i;

const stat = (n: number | undefined) =>
  n === undefined ? "" : n === Math.round(n) ? n.toFixed(0) : n.toFixed(1);

const percent = (r: RateRow | undefined) =>
  r === undefined || r.total === 0
    ? ""
    : `${Math.round((r.successes / r.total) * 100)}%`;

export function buildSummaryCsv(
  config: ScoutConfig,
  entries: EventEntry[],
  teams: number[],
  eventKey: string,
): string {
  const byTeam = new Map<number, EventEntry[]>();
  for (const entry of entries) {
    if (entry.teamNumber <= 0) continue;
    byTeam.set(entry.teamNumber, [
      ...(byTeam.get(entry.teamNumber) ?? []),
      entry,
    ]);
  }
  const all = [...new Set([...teams, ...byTeam.keys()])].sort((a, b) => a - b);
  const computed = all.map((team) => {
    const inputs = (byTeam.get(team) ?? []).map((e) => ({
      id: e.id,
      matchKey: entryMatchKey(e),
      fieldValues: e.fieldValues,
    }));
    return {
      team,
      stats: computeStats(config, inputs),
      phases: phaseStats(config, inputs),
    };
  });

  const climbs = allFields(config)
    .filter(
      (f) =>
        f.type === "select" &&
        climbField.test(`${f.title} ${f.code}`) &&
        (f.choices ?? []).some(([key, label]) => /^fail/i.test(key + label)),
    )
    .map((f) => ({ code: f.code, label: f.title.trim() || f.code }));

  const lines = [
    csvLine([
      "Event",
      "Team",
      "Matches",
      "IQM Teleop",
      "Max Teleop",
      "IQM Auto",
      "Max Auto",
      ...climbs.map((c) => `${c.label} success`),
    ]),
  ];
  for (const { team, stats, phases } of computed) {
    lines.push(
      csvLine([
        eventKey,
        String(team),
        String(stats.matches),
        stat(phases.teleop?.iqm),
        stat(phases.teleop?.max),
        stat(phases.auto?.iqm),
        stat(phases.auto?.max),
        ...climbs.map((c) =>
          percent(stats.rates.find((r) => r.code === c.code)),
        ),
      ]),
    );
  }
  return lines.join("\r\n");
}

export function summaryFileName(eventKey: string): string {
  const slug = eventKey
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return slug === "" ? "team-summary.csv" : `${slug}-team-summary.csv`;
}
