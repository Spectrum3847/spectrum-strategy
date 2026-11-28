import {
  allFields,
  effectiveDefault,
  type ScoutConfig,
  type Values,
} from "./config";
import {
  nextMatchNumberFor,
  type SavedRef,
  type ScheduledMatch,
  stationOf,
  teamForStation,
} from "./schedule";

export const matchCode = "matchNumber";
export const stationCode = "robot";
const teamCode = "pTnumber";

export interface FormContext {
  config: ScoutConfig;
  schedule: ScheduledMatch[];
  saved: SavedRef[];
}

export interface FormState {
  values: Values;
  matchFresh: boolean;
  matchFromAnchor: boolean;
}

const matchNumberOf = (values: Values): number | null => {
  const n = Number.parseInt(String(values[matchCode] ?? "").trim(), 10);
  return Number.isInteger(n) ? n : null;
};

function fillTeam(ctx: FormContext, values: Values): Values {
  const next = { ...values };
  const station = stationOf(next);
  const team = teamForStation(ctx.schedule, matchNumberOf(next), station);
  if (team === null) return next;
  const fields = allFields(ctx.config);
  if (fields.some((f) => f.code === teamCode)) next[teamCode] = String(team);
  for (const field of fields) {
    if (field.type !== "tbaTeamAndRobot") continue;
    const existing = next[field.code];
    const held =
      typeof existing === "object" && existing !== null
        ? String((existing as Record<string, unknown>).robotPosition ?? "")
        : "";
    const robotStation = String(next[stationCode] ?? "").trim() || held;
    const robotTeam = teamForStation(
      ctx.schedule,
      matchNumberOf(next),
      robotStation,
    );
    if (robotTeam !== null) {
      next[field.code] = {
        teamNumber: robotTeam,
        robotPosition: robotStation.toUpperCase().replace(/\s+/g, ""),
      };
    }
  }
  return next;
}

function anchor(state: FormState, ctx: FormContext): FormState {
  const scheduled = nextMatchNumberFor(
    stationOf(state.values),
    ctx.schedule,
    ctx.saved,
  );
  if (scheduled === null) return state;
  const values = fillTeam(ctx, {
    ...state.values,
    [matchCode]: String(scheduled),
  });
  return { values, matchFresh: state.matchFresh, matchFromAnchor: true };
}

export function initForm(
  ctx: FormContext,
  deviceStation: string | null,
): FormState {
  const values: Values = {};
  for (const field of allFields(ctx.config)) {
    values[field.code] = effectiveDefault(field);
  }
  const hasStation = allFields(ctx.config).some((f) => f.code === stationCode);
  if (deviceStation && hasStation) values[stationCode] = deviceStation;
  return anchor({ values, matchFresh: true, matchFromAnchor: false }, ctx);
}

export function applySchedule(state: FormState, ctx: FormContext): FormState {
  return state.matchFresh ? anchor(state, ctx) : state;
}

export function setValue(
  state: FormState,
  ctx: FormContext,
  code: string,
  value: unknown,
): FormState {
  let next: FormState = {
    ...state,
    values: { ...state.values, [code]: value },
  };
  if (code === matchCode) {
    next = { ...next, matchFresh: false, matchFromAnchor: false };
  }
  if (code === stationCode && next.matchFromAnchor) {
    const scheduled = nextMatchNumberFor(
      stationOf(next.values),
      ctx.schedule,
      ctx.saved,
    );
    if (scheduled !== null) {
      next = {
        ...next,
        values: { ...next.values, [matchCode]: String(scheduled) },
      };
    }
  }
  if (code === stationCode || code === matchCode) {
    next = { ...next, values: fillTeam(ctx, next.values) };
  }
  return next;
}

export function resetForNext(state: FormState, ctx: FormContext): FormState {
  const values: Values = { ...state.values };
  let matchFromAnchor = state.matchFromAnchor;
  for (const field of allFields(ctx.config)) {
    if (field.type === "actionTracker") {
      if (field.resetBehavior === "reset") {
        for (const action of field.actions) {
          values[`${field.code}_${action.code}_count`] = 0;
          values[`${field.code}_${action.code}_times`] = "";
        }
      }
      continue;
    }
    if (
      field.type === "tbaTeamAndRobot" &&
      field.resetBehavior === "increment"
    ) {
      values[field.code] = effectiveDefault(field);
      continue;
    }
    if (field.type === "tbaMatchNumber") {
      const scheduled = nextMatchNumberFor(
        stationOf(values),
        ctx.schedule,
        ctx.saved,
      );
      if (scheduled !== null) {
        values[field.code] = String(scheduled);
        matchFromAnchor = true;
      } else {
        values[field.code] = String((matchNumberOf(values) ?? 0) + 1);
        matchFromAnchor = false;
      }
      continue;
    }
    if (field.resetBehavior === "reset") {
      values[field.code] = effectiveDefault(field);
    } else if (field.resetBehavior === "increment") {
      const n = Number.parseInt(String(values[field.code] ?? ""), 10);
      values[field.code] = (Number.isInteger(n) ? n : 0) + 1;
    }
  }
  return {
    values: fillTeam(ctx, values),
    matchFresh: false,
    matchFromAnchor,
  };
}
