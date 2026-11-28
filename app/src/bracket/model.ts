export interface Strength {
  score: number;
  sigma: number;
}
type Slot = ["seed" | "winner" | "loser", number];
export interface Match {
  a: Slot;
  b: Slot;
  round: number;
}
const s = (n: number): Slot => ["seed", n];
const w = (n: number): Slot => ["winner", n];
const l = (n: number): Slot => ["loser", n];
export const matches: Match[] = [
  { a: s(1), b: s(8), round: 0 },
  { a: s(4), b: s(5), round: 0 },
  { a: s(2), b: s(7), round: 0 },
  { a: s(3), b: s(6), round: 0 },
  { a: l(1), b: l(2), round: 1 },
  { a: l(3), b: l(4), round: 1 },
  { a: w(1), b: w(2), round: 1 },
  { a: w(3), b: w(4), round: 1 },
  { a: l(7), b: w(6), round: 2 },
  { a: l(8), b: w(5), round: 2 },
  { a: w(7), b: w(8), round: 3 },
  { a: w(9), b: w(10), round: 3 },
  { a: l(11), b: w(12), round: 4 },
  { a: w(11), b: w(13), round: 5 },
];
const logisticScale = 1.7;

export function seeded(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function model(alliances: number[][], stats: Map<number, Strength>) {
  if (alliances.length !== 8) throw new Error("Eight alliances required");
  const strengths = alliances.map((teams) =>
    teams
      .map((team) => stats.get(team) ?? { score: 0, sigma: 20 })
      .sort((a, b) => b.score - a.score)
      .slice(0, 3),
  );
  const scores = strengths.map((a) => a.reduce((sum, x) => sum + x.score, 0));
  const variance = strengths.map(
    (a) => a.reduce((sum, x) => sum + x.sigma ** 2, 0) || 1,
  );
  const chances = scores.map((score, a) =>
    scores.map(
      (other, b) =>
        1 /
        (1 +
          Math.exp(
            (-logisticScale * (score - other)) /
              Math.sqrt((variance[a] ?? 1) + (variance[b] ?? 1)),
          )),
    ),
  );
  const chance = (a: number, b: number, finals = false) => {
    const p = chances[a - 1]?.[b - 1] ?? 0.5;
    return finals ? p * p * (3 - 2 * p) : p;
  };
  function run(through = 14, random?: () => number) {
    const winners = Array<number>(15).fill(0),
      losers = Array<number>(15).fill(0);
    const resolve = ([kind, n]: Slot) =>
      kind === "seed"
        ? n
        : kind === "winner"
          ? (winners[n] ?? 0)
          : (losers[n] ?? 0);
    const played = matches.map((m, i) => {
      const a = resolve(m.a),
        b = resolve(m.b),
        p = a && b ? chance(a, b, i === 13) : null;
      const winner =
        p !== null && i < through
          ? (random ? random() < p : p >= 0.5)
            ? a
            : b
          : 0;
      winners[i + 1] = winner;
      losers[i + 1] = winner ? (winner === a ? b : a) : 0;
      return { ...m, aSeed: a, bSeed: b, chance: p, winner };
    });
    return { played, champion: winners[14] ?? 0 };
  }
  function odds(count = 5000, seed = 3847) {
    const random = seeded(seed),
      title = Array<number>(8).fill(0),
      finals = Array<number>(8).fill(0);
    const winners = Array<number>(15).fill(0),
      losers = Array<number>(15).fill(0);
    const resolve = ([kind, n]: Slot) =>
      kind === "seed"
        ? n
        : kind === "winner"
          ? (winners[n] ?? 0)
          : (losers[n] ?? 0);
    for (let k = 0; k < count; k++) {
      for (let i = 0; i < matches.length; i++) {
        const m = matches[i];
        if (!m) continue;
        const a = resolve(m.a),
          b = resolve(m.b);
        if (i === 13) {
          finals[a - 1] = (finals[a - 1] ?? 0) + 1;
          finals[b - 1] = (finals[b - 1] ?? 0) + 1;
        }
        const winner = random() < chance(a, b, i === 13) ? a : b;
        winners[i + 1] = winner;
        losers[i + 1] = winner === a ? b : a;
      }
      const champion = winners[14] ?? 1;
      title[champion - 1] = (title[champion - 1] ?? 0) + 1;
    }
    return {
      title: title.map((n) => n / count),
      finals: finals.map((n) => n / count),
    };
  }
  return { scores, chance, run, odds };
}
