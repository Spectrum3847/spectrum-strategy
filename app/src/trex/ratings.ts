import type { TrexReport } from "../data/parse";
import { traitLabel, traits } from "./traits";

export interface TraitRating {
  key: string;
  label: string;
  average: number;
  count: number;
}

export function traitRatings(reports: TrexReport[]): TraitRating[] {
  const sums = new Map<string, { total: number; count: number }>();
  for (const r of reports) {
    if (r.rating === null) continue;
    const sum = sums.get(r.trait) ?? { total: 0, count: 0 };
    sum.total += r.rating;
    sum.count += 1;
    sums.set(r.trait, sum);
  }
  const order = (key: string) => {
    const at = traits.findIndex((t) => t.key === key);
    return at === -1 ? traits.length : at;
  };
  return [...sums.entries()]
    .sort(([a], [b]) => order(a) - order(b) || a.localeCompare(b))
    .map(([key, { total, count }]) => ({
      key,
      label: traitLabel(key),
      average: total / count,
      count,
    }));
}

export const ratingText = (r: TraitRating) =>
  `${r.average.toFixed(1)} from ${r.count} ${r.count === 1 ? "rating" : "ratings"}`;

export function ratingsByTeam(
  reports: TrexReport[],
): Map<number, TraitRating[]> {
  const byTeam = new Map<number, TrexReport[]>();
  for (const r of reports) {
    const list = byTeam.get(r.teamNumber) ?? [];
    list.push(r);
    byTeam.set(r.teamNumber, list);
  }
  return new Map(
    [...byTeam.entries()].map(([team, list]) => [team, traitRatings(list)]),
  );
}
