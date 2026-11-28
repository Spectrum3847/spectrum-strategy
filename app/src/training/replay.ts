import { type CompLevel, matchLabel, matchOrder } from "../data/matchKey";
import type { EventMatch, EventTeam, TeamRanking } from "../data/tbaEvent";
import type { ScheduledMatch } from "../scout/schedule";

export interface Replay {
  teams: EventTeam[];
  matches: ScheduledMatch[];
}

export const hasResult = (m: ScheduledMatch) =>
  (m.redScore ?? -1) >= 0 && (m.blueScore ?? -1) >= 0;

export function buildReplay(
  matches: ScheduledMatch[],
  teams: EventTeam[],
): Replay {
  return {
    teams,
    matches: matches
      .filter(hasResult)
      .map((m) => ({ ...m, time: null, predictedTime: null }))
      .sort((a, b) => matchOrder(a.key) - matchOrder(b.key)),
  };
}

export function scheduleAt(replay: Replay, revealed: number): ScheduledMatch[] {
  return replay.matches.map((m, i) =>
    i < revealed ? m : { ...m, redScore: -1, blueScore: -1 },
  );
}

export function eventMatchesFrom(schedule: ScheduledMatch[]): EventMatch[] {
  return schedule.map((m) => {
    const played = hasResult(m);
    const red = m.redScore ?? -1;
    const blue = m.blueScore ?? -1;
    return {
      key: m.key,
      level: m.compLevel as CompLevel,
      red: m.red,
      blue: m.blue,
      redScore: played ? red : null,
      blueScore: played ? blue : null,
      winner: !played || red === blue ? null : red > blue ? "red" : "blue",
    };
  });
}

export function rankingsAt(schedule: ScheduledMatch[]): TeamRanking[] {
  const record = new Map<number, TeamRanking>();
  const row = (team: number) => {
    let r = record.get(team);
    if (!r) {
      r = { team, rank: 0, wins: 0, losses: 0, ties: 0 };
      record.set(team, r);
    }
    return r;
  };
  let played = 0;
  for (const m of schedule) {
    if (m.compLevel !== "qm") continue;
    for (const team of [...m.red, ...m.blue]) row(team);
    if (!hasResult(m)) continue;
    played += 1;
    const red = m.redScore ?? 0;
    const blue = m.blueScore ?? 0;
    for (const team of m.red) {
      const r = row(team);
      if (red > blue) r.wins += 1;
      else if (red < blue) r.losses += 1;
      else r.ties += 1;
    }
    for (const team of m.blue) {
      const r = row(team);
      if (blue > red) r.wins += 1;
      else if (blue < red) r.losses += 1;
      else r.ties += 1;
    }
  }
  if (played === 0) return [];
  const points = (r: TeamRanking) => r.wins * 2 + r.ties;
  return [...record.values()]
    .sort((a, b) => points(b) - points(a) || b.wins - a.wins || a.team - b.team)
    .map((r, i) => ({ ...r, rank: i + 1 }));
}

export function nextLabel(replay: Replay, revealed: number): string | null {
  const next = replay.matches[revealed];
  return next ? matchLabel(next.key) : null;
}
