import { compareMatches, isPlayed } from "../now/matches";
import type { ScheduledMatch } from "../scout/schedule";

export type Side = "Red" | "Blue";

export const involves = (m: ScheduledMatch, team: number) =>
  m.red.includes(team) || m.blue.includes(team);

export interface ScheduleRows {
  upcoming: ScheduledMatch[];
  played: ScheduledMatch[];
}

export function splitSchedule(
  schedule: ScheduledMatch[],
  ourTeam: number | null,
  onlyOurs: boolean,
): ScheduleRows {
  const ordered = schedule
    .filter((m) => !onlyOurs || ourTeam === null || involves(m, ourTeam))
    .sort(compareMatches);
  return {
    upcoming: ordered.filter((m) => !isPlayed(m)),
    played: ordered.filter(isPlayed).reverse(),
  };
}

export function winnerOf(m: ScheduledMatch): Side | "Tie" | null {
  if (!isPlayed(m)) return null;
  const red = m.redScore ?? 0;
  const blue = m.blueScore ?? 0;
  if (red === blue) return "Tie";
  return red > blue ? "Red" : "Blue";
}

export function ourSide(m: ScheduledMatch, team: number | null): Side | null {
  if (team === null) return null;
  if (m.red.includes(team)) return "Red";
  return m.blue.includes(team) ? "Blue" : null;
}

export function resultText(m: ScheduledMatch): string | null {
  const winner = winnerOf(m);
  if (winner === null) return null;
  return winner === "Tie" ? "Tie" : `${winner} won`;
}

export function ourOutcome(
  m: ScheduledMatch,
  team: number | null,
): "won" | "lost" | "tied" | null {
  const side = ourSide(m, team);
  const winner = winnerOf(m);
  if (side === null || winner === null) return null;
  if (winner === "Tie") return "tied";
  return winner === side ? "won" : "lost";
}
