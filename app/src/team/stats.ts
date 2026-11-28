import { matchOrder } from "../data/matchKey";
import { isContradictedNoShow, isNoShowAnswer } from "../export/csv";
import {
  allFields,
  labelForStored,
  type ScoutConfig,
  type ScoutField,
  type Values,
} from "../scout/config";
import { teamCodes } from "../scout/entry";
import { type LeftOut, mean, spreadOf, type Trend, trendOf } from "./spread";
import { troubleTitle } from "./titles";

export { mean };

export interface StatInput {
  id: string;
  matchKey: string;
  fieldValues: Values;
}

export interface MatchGroup {
  key: string;
  entries: StatInput[];
}

export function groupByMatch(inputs: StatInput[]): MatchGroup[] {
  const groups = new Map<string, MatchGroup>();
  for (const input of inputs) {
    const group = groups.get(input.matchKey);
    if (group) group.entries.push(input);
    else groups.set(input.matchKey, { key: input.matchKey, entries: [input] });
  }
  return [...groups.values()].sort(
    (a, b) => matchOrder(a.key) - matchOrder(b.key),
  );
}

export function numberOf(raw: unknown): number | null {
  if (typeof raw === "number") return Number.isFinite(raw) ? raw : null;
  if (typeof raw === "string" && raw.trim() !== "") {
    const n = Number(raw);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export function iqm(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const n = sorted.length;
  if (n === 0) return 0;
  if (n < 4) return mean(sorted);
  const quarter = n / 4;
  const cut = Math.floor(quarter);
  const edge = 1 - (quarter - cut);
  let sum = edge * ((sorted[cut] ?? 0) + (sorted[n - 1 - cut] ?? 0));
  for (let i = cut + 1; i < n - 1 - cut; i++) sum += sorted[i] ?? 0;
  return sum / (n / 2);
}

export function sd(values: number[]): number {
  const m = mean(values);
  return Math.sqrt(mean(values.map((v) => (v - m) ** 2)));
}

export interface StatRow {
  code: string;
  label: string;
  section: string;
  n: number;
  mean: number;
  iqm: number;
  max: number;
  sd: number | null;
  typical: number;
  typicalN: number;
  se: number | null;
  range: [number, number] | null;
  floor: number | null;
  leftOut: LeftOut[];
}

function summarize(
  code: string,
  label: string,
  section: string,
  values: Map<string, number>,
  broken: Set<string>,
): StatRow | null {
  const all = [...values.values()];
  const spread = spreadOf(
    [...values].map(([key, value]) => ({
      key,
      value,
      broken: broken.has(key),
    })),
  );
  if (!spread) return null;
  return {
    code,
    label,
    section,
    n: all.length,
    mean: mean(all),
    iqm: iqm(all),
    max: Math.max(...all),
    sd: all.length < 2 ? null : sd(all),
    ...spread,
  };
}

export type Outcome = "positive" | "failed" | "none";

const notTried = /^(n\/?a|not attempted|none|no|false|no card.*)$/i;
const failedTry = /^fail/i;

function classify(label: string): Outcome {
  const text = label.trim();
  if (text === "") return "none";
  if (notTried.test(text)) return "none";
  if (failedTry.test(text)) return "failed";
  return "positive";
}

function selectOutcome(field: ScoutField, raw: unknown): Outcome | null {
  const stored = raw === undefined || raw === null ? "" : String(raw);
  if (stored.trim() === "") return null;
  const found = classify(labelForStored(field, stored));
  return found === "positive" && classify(stored) === "none" ? "none" : found;
}

function booleanOutcome(raw: unknown): Outcome | null {
  if (raw === true || raw === "true") return "positive";
  if (raw === false || raw === "false") return "none";
  return null;
}

function isOutcomeSelect(field: ScoutField): boolean {
  if (field.type !== "select" || !field.choices) return false;
  const found = new Set<Outcome>();
  for (const [key, label] of field.choices) {
    found.add(classify(label));
    if (classify(key) === "none") found.add("none");
  }
  return found.has("positive") && (found.has("none") || found.has("failed"));
}

export interface MatchOutcome {
  key: string;
  outcome: Outcome;
}

export function outcomes(
  field: ScoutField,
  groups: MatchGroup[],
): MatchOutcome[] | null {
  const read =
    field.type === "boolean"
      ? booleanOutcome
      : isOutcomeSelect(field)
        ? (raw: unknown) => selectOutcome(field, raw)
        : null;
  if (!read) return null;
  const out: MatchOutcome[] = [];
  for (const group of groups) {
    const votes = group.entries
      .map((e) => read(e.fieldValues[field.code]))
      .filter((v): v is Outcome => v !== null);
    if (votes.length === 0) continue;
    const positive = votes.filter((v) => v === "positive").length;
    const outcome: Outcome =
      positive * 2 > votes.length
        ? "positive"
        : votes.includes("failed")
          ? "failed"
          : "none";
    out.push({ key: group.key, outcome });
  }
  return out;
}

export function breakdownKeys(
  config: ScoutConfig,
  groups: MatchGroup[],
): Set<string> {
  const fields = allFields(config);
  const broken = new Set<string>();
  for (const field of fields) {
    if (field.type !== "boolean") continue;
    if (!troubleTitle.test(field.title.trim() || field.code)) continue;
    for (const { key, outcome } of outcomes(field, groups) ?? []) {
      if (outcome === "positive") broken.add(key);
    }
  }
  const starts = fields.filter((f) => f.type === "select");
  const noShow = (values: Values) =>
    starts.some(
      (f) =>
        isNoShowAnswer(f, values) && !isContradictedNoShow(f, values, config),
    );
  for (const group of groups) {
    const votes = group.entries.filter((e) => noShow(e.fieldValues)).length;
    if (votes * 2 > group.entries.length) broken.add(group.key);
  }
  return broken;
}

export interface Reliability {
  ok: number;
  of: number;
}

export interface RateRow {
  code: string;
  label: string;
  section: string;
  successes: number;
  total: number;
}

export interface SeriesPoint {
  key: string;
  value: number;
}

export interface TeamStats {
  matches: number;
  total: StatRow | null;
  rows: StatRow[];
  rates: RateRow[];
  series: SeriesPoint[];
  reliability: Reliability;
  trend: Trend | null;
}

interface NumericDef {
  code: string;
  label: string;
  section: string;
  additive: boolean;
}

const phaseSection = /auto|tele|end|climb/i;
const notMetrics = new Set([...teamCodes, "matchNumber"]);

function numericDefs(config: ScoutConfig): NumericDef[] {
  const defs: NumericDef[] = [];
  for (const section of config.sections) {
    for (const field of section.fields) {
      const label = field.title.trim() || field.code;
      if (field.type === "actionTracker") {
        for (const action of field.actions) {
          defs.push({
            code: `${field.code}_${action.code}_count`,
            label: action.label,
            section: section.name,
            additive: false,
          });
        }
        continue;
      }
      const counted = field.type === "counter" || field.type === "multiCounter";
      if (
        (counted || field.type === "number" || field.type === "range") &&
        !notMetrics.has(field.code)
      ) {
        defs.push({
          code: field.code,
          label,
          section: section.name,
          additive: counted && phaseSection.test(section.name),
        });
      }
    }
  }
  return defs;
}

function perMatch(code: string, groups: MatchGroup[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const group of groups) {
    const values = group.entries
      .map((e) => numberOf(e.fieldValues[code]))
      .filter((v): v is number => v !== null);
    if (values.length > 0) out.set(group.key, mean(values));
  }
  return out;
}

export function entryMatchKey(entry: {
  id: string;
  tbaMatchKey: string | null;
  fieldValues: Values;
}): string {
  if (entry.tbaMatchKey) return entry.tbaMatchKey.toLowerCase();
  const typed = String(entry.fieldValues.matchNumber ?? "").trim();
  return typed === "" ? entry.id : `typed:${typed}`;
}

const autoSection = /auto/i;
const teleSection = /tele/i;

export function autoPointsOf(
  config: ScoutConfig,
  values: Values,
): number | null {
  let sum = 0;
  let seen = false;
  for (const def of numericDefs(config)) {
    if (!def.additive || !autoSection.test(def.section)) continue;
    const n = numberOf(values[def.code]);
    if (n === null) continue;
    sum += n;
    seen = true;
  }
  return seen ? sum : null;
}

export function phaseStats(
  config: ScoutConfig,
  inputs: StatInput[],
): { auto: StatRow | null; teleop: StatRow | null } {
  const groups = groupByMatch(inputs);
  const broken = breakdownKeys(config, groups);
  const counters = numericDefs(config).filter((d) => d.additive);
  const phase = (code: string, label: string, sections: RegExp) => {
    const totals = new Map<string, number>();
    for (const def of counters) {
      if (!sections.test(def.section)) continue;
      for (const [key, value] of perMatch(def.code, groups)) {
        totals.set(key, (totals.get(key) ?? 0) + value);
      }
    }
    return summarize(code, label, "", totals, broken);
  };
  return {
    auto: phase("auto", "Auto", autoSection),
    teleop: phase("teleop", "Teleop", teleSection),
  };
}

export interface PhaseMatch {
  key: string;
  total: number;
  auto: number;
  teleop: number;
  endgame: number;
  penalties: number;
}

const endSection = /end|climb/i;
const penaltyLabel = /foul|penalt/i;

export function matchScores(
  config: ScoutConfig,
  inputs: StatInput[],
): PhaseMatch[] {
  const groups = groupByMatch(inputs);
  const defs = numericDefs(config);
  const sum = (picked: NumericDef[]) => {
    const totals = new Map<string, number>();
    for (const def of picked) {
      for (const [key, value] of perMatch(def.code, groups)) {
        totals.set(key, (totals.get(key) ?? 0) + value);
      }
    }
    return totals;
  };
  const counters = defs.filter((d) => d.additive);
  const total = sum(counters);
  const auto = sum(counters.filter((d) => autoSection.test(d.section)));
  const teleop = sum(counters.filter((d) => teleSection.test(d.section)));
  const endgame = sum(
    counters.filter(
      (d) =>
        endSection.test(d.section) &&
        !autoSection.test(d.section) &&
        !teleSection.test(d.section),
    ),
  );
  const penalties = sum(defs.filter((d) => penaltyLabel.test(d.label)));
  return groups
    .filter((g) => total.has(g.key))
    .map((g) => ({
      key: g.key,
      total: total.get(g.key) ?? 0,
      auto: auto.get(g.key) ?? 0,
      teleop: teleop.get(g.key) ?? 0,
      endgame: endgame.get(g.key) ?? 0,
      penalties: Math.round(penalties.get(g.key) ?? 0),
    }));
}

export function computeStats(
  config: ScoutConfig,
  inputs: StatInput[],
): TeamStats {
  const groups = groupByMatch(inputs);
  const broken = breakdownKeys(config, groups);
  const defs = numericDefs(config);
  const rows: StatRow[] = [];
  const totals = new Map<string, number>();
  for (const def of defs) {
    const values = perMatch(def.code, groups);
    const row = summarize(def.code, def.label, def.section, values, broken);
    if (row) rows.push(row);
    if (def.additive) {
      for (const [key, value] of values) {
        totals.set(key, (totals.get(key) ?? 0) + value);
      }
    }
  }
  const series = groups
    .filter((g) => totals.has(g.key))
    .map((g) => ({ key: g.key, value: totals.get(g.key) ?? 0 }));

  const rates: RateRow[] = [];
  for (const section of config.sections) {
    for (const field of section.fields) {
      const found = outcomes(field, groups);
      if (!found || found.length === 0) continue;
      rates.push({
        code: field.code,
        label: field.title.trim() || field.code,
        section: section.name,
        successes: found.filter((o) => o.outcome === "positive").length,
        total: found.length,
      });
    }
  }

  return {
    matches: groups.length,
    total: summarize(
      "total",
      "Match total",
      "",
      new Map(series.map((p) => [p.key, p.value])),
      broken,
    ),
    rows,
    rates,
    series,
    reliability: {
      ok: groups.filter((g) => !broken.has(g.key)).length,
      of: groups.length,
    },
    trend: trendOf(series.filter((p) => !broken.has(p.key))),
  };
}
