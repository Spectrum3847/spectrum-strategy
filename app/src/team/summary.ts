import { matchLabel } from "../data/matchKey";
import { allFields, type ScoutConfig, type ScoutField } from "../scout/config";
import type { Trend, TrendDirection } from "./spread";
import {
  type MatchGroup,
  outcomes,
  type StatRow,
  type TeamStats,
} from "./stats";
import { troubleTitle } from "./titles";

export interface MatchCite {
  key: string;
  label: string;
}

export interface SummaryLine {
  text: string;
  matches: MatchCite[];
}

export interface CommentSummary {
  trend: { direction: TrendDirection; line: SummaryLine } | null;
  strengths: SummaryLine[];
  concerns: SummaryLine[];
  roles: SummaryLine[];
}

export const minAttempts = 3;
export const reliableRate = 0.8;
export const unreliableRate = 0.5;
export const minRoleMatches = 2;
export const rolePercent = 30;

const cardTitle = /card|foul|penalt/i;
const climbTitle = /climb/i;
export const roleTitle = /defen[cs]e|pass|push|feed/i;

const cite = (key: string): MatchCite => ({ key, label: matchLabel(key) });

const failable = (field: ScoutField) =>
  (field.choices ?? []).some(([key, label]) => /^fail/i.test(label + key));

function trendLine(
  trend: Trend | null,
  total: StatRow | null,
): CommentSummary["trend"] {
  if (trend === null || total === null) return null;
  const { direction, earlier, later } = trend;
  if (direction === "steady") {
    const error = total.se === null ? "" : ` ±${Math.round(total.se)}`;
    const usual = total.range
      ? `, usually ${Math.round(total.range[0])} to ${Math.round(total.range[1])}`
      : "";
    return {
      direction,
      line: {
        text: `Steady: typically ${Math.round(total.typical)}${error}${usual}`,
        matches: [],
      },
    };
  }
  const word = direction === "improving" ? "Improving" : "Declining";
  return {
    direction,
    line: {
      text: `${word}: later matches average ${Math.round(later)} against ${Math.round(earlier)} earlier, more than normal swings`,
      matches: trend.laterKeys.map(cite),
    },
  };
}

export function buildSummary(
  config: ScoutConfig,
  groups: MatchGroup[],
  stats: Pick<TeamStats, "trend" | "total"> | null,
): CommentSummary {
  const strengths: SummaryLine[] = [];
  const concerns: SummaryLine[] = [];
  const roles: SummaryLine[] = [];

  for (const field of allFields(config)) {
    const found = outcomes(field, groups);
    if (!found || found.length === 0) continue;
    const title = field.title.trim() || field.code;
    const positive = found.filter((o) => o.outcome === "positive");
    const failed = found.filter((o) => o.outcome === "failed");

    if (
      field.type === "boolean" &&
      troubleTitle.test(title) &&
      positive.length > 0
    ) {
      concerns.push({
        text: `${title}: ${positive.length} of ${found.length} matches`,
        matches: positive.map((o) => cite(o.key)),
      });
    } else if (cardTitle.test(title) && positive.length > 0) {
      concerns.push({
        text: `${title}: ${positive.length} of ${found.length} matches`,
        matches: positive.map((o) => cite(o.key)),
      });
    } else if (
      field.type === "select" &&
      climbTitle.test(title) &&
      failable(field)
    ) {
      const attempts = positive.length + failed.length;
      if (attempts < minAttempts) continue;
      const rate = positive.length / attempts;
      const text = `${title}: ${positive.length} of ${attempts} attempts succeeded`;
      if (rate >= reliableRate) {
        strengths.push({ text, matches: positive.map((o) => cite(o.key)) });
      } else if (rate < unreliableRate) {
        concerns.push({ text, matches: failed.map((o) => cite(o.key)) });
      }
    } else if (
      field.type === "boolean" &&
      roleTitle.test(title) &&
      found.length >= minRoleMatches &&
      positive.length * 100 >= found.length * rolePercent
    ) {
      roles.push({
        text: `${title}: ${positive.length} of ${found.length} matches`,
        matches: positive.map((o) => cite(o.key)),
      });
    }
  }

  return {
    trend: trendLine(stats?.trend ?? null, stats?.total ?? null),
    strengths,
    concerns,
    roles,
  };
}

export const isEmptySummary = (s: CommentSummary) =>
  s.trend === null &&
  s.strengths.length === 0 &&
  s.concerns.length === 0 &&
  s.roles.length === 0;
