import type { CompareFacts } from "../assistant/teamCompare";
import type { EventEntry } from "../data/parse";
import { incidentsByTeam } from "../picks/incidents";
import { allFields, type ScoutConfig } from "../scout/config";
import { commentsFor } from "../team/format";
import {
  entryMatchKey,
  groupByMatch,
  outcomes,
  phaseStats,
  type StatInput,
} from "../team/stats";

function climbSuccessRate(
  config: ScoutConfig,
  inputs: StatInput[],
): number | null {
  const groups = groupByMatch(inputs);
  const tried = new Set<string>();
  const made = new Set<string>();
  for (const field of allFields(config)) {
    if (field.type !== "select" || !/climb/i.test(field.title)) continue;
    for (const { key, outcome } of outcomes(field, groups) ?? []) {
      if (outcome !== "none") tried.add(key);
      if (outcome === "positive") made.add(key);
    }
  }
  return tried.size === 0 ? null : made.size / tried.size;
}

export function compareFacts(
  config: ScoutConfig,
  entries: EventEntry[],
  team: number,
): { scouted: number; facts: CompareFacts } {
  const mine = entries.filter((e) => e.teamNumber === team);
  const inputs = mine.map((e) => ({
    id: e.id,
    matchKey: entryMatchKey(e),
    fieldValues: e.fieldValues,
  }));
  const phases = phaseStats(config, inputs);
  const found = incidentsByTeam(mine).get(team);
  return {
    scouted: mine.length,
    facts: {
      teleopIqm: phases.teleop?.iqm ?? null,
      autoIqm: phases.auto?.iqm ?? null,
      climbSuccessRate: climbSuccessRate(config, inputs),
      cards: found
        ? found.red.length + found.yellow.length + found.unknown.length
        : 0,
      disconnects: found?.died.length ?? 0,
      comments: commentsFor(config, mine).map((c) => c.text),
    },
  };
}
