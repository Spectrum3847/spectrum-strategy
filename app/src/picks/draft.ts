export interface DraftAction {
  team: number;
  declined: boolean;
}

export interface Alliance {
  captain: number;
  picks: number[];
  teams: number[];
}

export const allianceCount = 8;
export const roundOptions = [2, 3] as const;
export type Rounds = (typeof roundOptions)[number];
export const defaultRounds: Rounds = 3;
export const backupCount = 8;

export interface DraftBoard {
  rounds: Rounds;
  order: number[];
  alliances: Alliance[];
  turn: number;
  taken: Set<number>;
  declined: Set<number>;
  picking: number | null;
}

const snake = (rounds: number): number[] =>
  Array.from({ length: rounds }, (_, round) => {
    const seats = Array.from({ length: allianceCount }, (_, i) => i);
    return round % 2 === 0 ? seats : seats.reverse();
  }).flat();

export function replayDraft(
  actions: DraftAction[],
  ranking: number[],
  rounds: Rounds = defaultRounds,
): DraftBoard {
  const taken = new Set<number>();
  const declined = new Set<number>();
  let seats: number[] = [];
  const picks = new Map<number, number[]>();

  const seat = () => {
    const captain = ranking.find((t) => !taken.has(t));
    if (captain === undefined) return;
    taken.add(captain);
    picks.set(captain, []);
    seats = [...seats, captain];
  };
  for (let i = 0; i < allianceCount; i++) seat();

  const order = snake(rounds);
  let turn = 0;
  const onTheClock = (): number | null => {
    while (turn < order.length && (order[turn] ?? 0) >= seats.length) turn++;
    return turn < order.length ? (order[turn] ?? null) : null;
  };

  const snapshot = (): DraftBoard => {
    const picking = onTheClock();
    return {
      rounds,
      order,
      turn,
      taken: new Set(taken),
      declined: new Set(declined),
      picking,
      alliances: seats.map((captain) => {
        const own = [...(picks.get(captain) ?? [])];
        return { captain, picks: own, teams: [captain, ...own] };
      }),
    };
  };

  for (const action of actions) {
    const at = onTheClock();
    if (at === null) break;
    if (!canInvite(snapshot(), action.team)) continue;
    if (action.declined) {
      declined.add(action.team);
      continue;
    }
    const picker = seats[at];
    if (picker === undefined) continue;
    const slot = seats.indexOf(action.team);
    if (slot >= 0) {
      seats = seats.filter((_, i) => i !== slot);
      picks.delete(action.team);
      seat();
    }
    picks.set(picker, [...(picks.get(picker) ?? []), action.team]);
    taken.add(action.team);
    turn++;
  }
  return snapshot();
}

export const isComplete = (board: DraftBoard) => board.picking === null;

export const allianceSize = (board: DraftBoard) => board.rounds + 1;

export const roundOf = (board: DraftBoard) =>
  Math.floor(board.turn / allianceCount);

export function canInvite(board: DraftBoard, team: number): boolean {
  const at = board.picking;
  if (at === null || board.declined.has(team)) return false;
  if (!board.taken.has(team)) return true;
  return board.alliances
    .slice(at + 1)
    .some((a) => a.captain === team && a.picks.length === 0);
}

export function picksUntil(board: DraftBoard, team: number): number | null {
  const seat = board.alliances.findIndex((a) => a.teams.includes(team));
  if (seat < 0) return null;
  let waiting = 0;
  for (const at of board.order.slice(board.turn)) {
    if (at >= board.alliances.length) continue;
    if (at === seat) return waiting;
    waiting++;
  }
  return null;
}

export function backups(board: DraftBoard, official: number[]): number[] {
  if (!isComplete(board) || board.rounds !== 2) return [];
  return official
    .filter((t) => !board.taken.has(t) && !board.declined.has(t))
    .slice(0, backupCount);
}

export function takenLabels(board: DraftBoard): Map<number, string> {
  const out = new Map<number, string>();
  board.alliances.forEach((a, i) => {
    out.set(a.captain, `Captain of alliance ${i + 1}`);
    for (const t of a.picks) out.set(t, `Picked by alliance ${i + 1}`);
  });
  return out;
}

export function seeding(
  official: number[],
  epa: Record<number, number> | null,
  teams: number[],
): number[] {
  const out: number[] = [];
  const seen = new Set<number>();
  const add = (t: number) => {
    if (!seen.has(t)) {
      seen.add(t);
      out.push(t);
    }
  };
  for (const t of official) add(t);
  const byEpa = Object.entries(epa ?? {})
    .map(([t, v]) => [Number(t), v] as const)
    .filter(([t]) => teams.includes(t))
    .sort((a, b) => b[1] - a[1]);
  for (const [t] of byEpa) add(t);
  for (const t of [...teams].sort((a, b) => a - b)) add(t);
  return out;
}

export function roundsForEventType(type: number | null): Rounds {
  if (type === null) return defaultRounds;
  return type === 3 || type === 4 ? 3 : 2;
}
