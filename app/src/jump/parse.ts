import { matchPath } from "../data/matchKey";
import { parseTeamNumber } from "../now/myTeam";

export interface MatchQuery {
  suffix: string;
  label: string;
}

const qualification = /^(?:qm|q|m|match)(\d+)$/;
const playoff = /^(sf|f)(\d+)(?:m(\d+))?$/;

export function parseMatchQuery(query: string): MatchQuery | null {
  const text = query.toLowerCase().replace(/[\s-]/g, "");
  const qual = qualification.exec(text);
  if (qual) {
    const n = Number(qual[1]);
    return n === 0 ? null : { suffix: `qm${n}`, label: `Qualification ${n}` };
  }
  const p = playoff.exec(text);
  if (!p) return null;
  const level = p[1] as "sf" | "f";
  const set = Number(p[2]);
  const game = p[3];
  if (set === 0 || game === "0") return null;
  const name = level === "sf" ? "Semifinal" : "Final";
  return {
    suffix: `${level}${set}m${game ?? 1}`,
    label:
      game === undefined ? `${name} ${set}` : `${name} ${set} match ${game}`,
  };
}

export interface JumpContext {
  eventKey: string;
  knownTeams: Set<number>;
  matchKeys: string[];
  canTeam: boolean;
  canMatch: boolean;
}

export type JumpResult =
  | { ok: true; kind: "team" | "match"; path: string; label: string }
  | { ok: false; message: string };

export const emptyMessage =
  "Enter a team number like 3847 or a match like q45.";

export function resolveJump(text: string, ctx: JumpContext): JumpResult {
  const query = parseMatchQuery(text);
  if (query) {
    if (!ctx.canMatch) {
      return { ok: false, message: "Your role cannot open match pages." };
    }
    if (ctx.eventKey === "") {
      return { ok: false, message: "No event is set. Set one in Settings." };
    }
    const wanted = `${ctx.eventKey}_${query.suffix}`.toLowerCase();
    const key = ctx.matchKeys.find((k) => k.toLowerCase() === wanted);
    return key === undefined
      ? { ok: false, message: `${query.label} is not in the schedule.` }
      : { ok: true, kind: "match", path: matchPath(key), label: query.label };
  }
  const team = parseTeamNumber(text);
  if (team === null) return { ok: false, message: emptyMessage };
  if (!ctx.canTeam) {
    return { ok: false, message: "Your role cannot open team pages." };
  }
  if (ctx.knownTeams.size > 0 && !ctx.knownTeams.has(team)) {
    return { ok: false, message: `Team ${team} is not at this event.` };
  }
  return {
    ok: true,
    kind: "team",
    path: `/teams/${team}`,
    label: `Team ${team}`,
  };
}
