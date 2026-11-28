import { resolveMatchKey, type ScheduledMatch } from "./schedule";

export function eventLinkMessage(
  eventKey: string,
  schedule: ScheduledMatch[],
  typedMatch: string,
): string {
  if (eventKey === "") {
    return "No event selected. Entries cannot be linked to the match schedule, so accuracy checks are off.";
  }
  const at = `Scouting at ${eventKey}.`;
  if (schedule.length === 0) {
    return `${at} The match schedule has not loaded yet, so this entry will skip accuracy checks.`;
  }
  const match = typedMatch.trim();
  if (match === "") {
    return `${at} Enter a match number to link this entry to the schedule for accuracy checks.`;
  }
  const key = resolveMatchKey(match, schedule);
  if (key === null) {
    return `${at} Match ${match} is not in the schedule, so this entry will skip accuracy checks.`;
  }
  return `${at} This entry links to ${key} for accuracy checks.`;
}
