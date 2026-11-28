export const mean = (values: number[]) =>
  values.reduce((a, b) => a + b, 0) / values.length;

export const minCleanMatches = 2;
export const minOutlierMatches = 5;
export const outlierMads = 2.5;
const madScale = 1.4826;
export const minFloorMatches = 4;
export const minTrendSamples = 6;
export const minTrendChange = 2;

export function sampleSd(values: number[]): number | null {
  if (values.length < 2) return null;
  const m = mean(values);
  const sum = values.reduce((acc, v) => acc + (v - m) ** 2, 0);
  return Math.sqrt(sum / (values.length - 1));
}

export function quantile(values: number[], p: number): number {
  const sorted = [...values].sort((a, b) => a - b);
  const at = (sorted.length - 1) * p;
  const low = Math.floor(at);
  const lower = sorted[low] ?? 0;
  const upper = sorted[Math.min(low + 1, sorted.length - 1)] ?? lower;
  return lower + (upper - lower) * (at - low);
}

export type LeftOutReason = "breakdown" | "low" | "high";

export interface LeftOut {
  key: string;
  value: number;
  reason: LeftOutReason;
}

export interface SpreadPoint {
  key: string;
  value: number;
  broken: boolean;
}

export interface Spread {
  typical: number;
  typicalN: number;
  se: number | null;
  range: [number, number] | null;
  floor: number | null;
  leftOut: LeftOut[];
}

function outlierKeys(points: SpreadPoint[]): Map<string, LeftOutReason> {
  const found = new Map<string, LeftOutReason>();
  if (points.length < minOutlierMatches) return found;
  const values = points.map((p) => p.value);
  const median = quantile(values, 0.5);
  const mad =
    madScale *
    quantile(
      values.map((v) => Math.abs(v - median)),
      0.5,
    );
  if (mad === 0) return found;
  for (const p of points) {
    if (Math.abs(p.value - median) > outlierMads * mad) {
      found.set(p.key, p.value < median ? "low" : "high");
    }
  }
  return found;
}

export function spreadOf(points: SpreadPoint[]): Spread | null {
  if (points.length === 0) return null;
  const normal = points.filter((p) => !p.broken);
  const reasons =
    normal.length < minCleanMatches
      ? new Map<string, LeftOutReason>()
      : outlierKeys(normal);
  if (normal.length >= minCleanMatches) {
    for (const p of points) if (p.broken) reasons.set(p.key, "breakdown");
  }
  const kept = points.filter((p) => !reasons.has(p.key)).map((p) => p.value);
  const sd = sampleSd(kept);
  const enough = kept.length >= minFloorMatches;
  return {
    typical: mean(kept),
    typicalN: kept.length,
    se: sd === null ? null : sd / Math.sqrt(kept.length),
    range: enough ? [quantile(kept, 0.25), quantile(kept, 0.75)] : null,
    floor: enough ? quantile(kept, 0.25) : null,
    leftOut: points.flatMap((p) => {
      const reason = reasons.get(p.key);
      return reason ? [{ key: p.key, value: p.value, reason }] : [];
    }),
  };
}

export type TrendDirection = "improving" | "declining" | "steady";

export interface TrendPoint {
  key: string;
  value: number;
}

export interface Trend {
  direction: TrendDirection;
  delta: number;
  earlier: number;
  later: number;
  laterKeys: string[];
}

export function trendOf(points: TrendPoint[]): Trend | null {
  if (points.length < minTrendSamples) return null;
  const split = Math.floor(points.length / 2);
  const first = points.slice(0, split).map((p) => p.value);
  const second = points.slice(split);
  const later = second.map((p) => p.value);
  const earlierMean = mean(first);
  const laterMean = mean(later);
  const delta = laterMean - earlierMean;
  const sdFirst = sampleSd(first);
  const sdLater = sampleSd(later);
  if (sdFirst === null || sdLater === null) return null;
  const noise =
    2 * Math.sqrt(sdFirst ** 2 / first.length + sdLater ** 2 / later.length);
  const real = Math.abs(delta) > noise && Math.abs(delta) >= minTrendChange;
  return {
    direction: real ? (delta > 0 ? "improving" : "declining") : "steady",
    delta,
    earlier: earlierMean,
    later: laterMean,
    laterKeys: second.map((p) => p.key),
  };
}

export interface Estimate {
  value: number;
  se: number | null;
}

export function tied(a: Estimate | null, b: Estimate | null): boolean {
  if (!a || !b || a.se === null || b.se === null) return false;
  return Math.abs(a.value - b.value) < Math.sqrt(a.se ** 2 + b.se ** 2);
}
