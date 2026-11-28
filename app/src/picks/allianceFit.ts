import type { TeamFacts } from "./facts";
import { describe } from "./incidents";

const bestThree = (teams: TeamFacts[]) =>
  Math.round(
    teams
      .map((t) => t.mean)
      .filter((n): n is number => n !== null)
      .sort((a, b) => b - a)
      .slice(0, 3)
      .reduce((a, b) => a + b, 0),
  );
const reliable = (team: TeamFacts) =>
  !!team.l3 &&
  team.l3.attempts >= 3 &&
  team.l3.successes * 3 >= team.l3.attempts * 2;

export function allianceFit(ours: TeamFacts[], candidate: TeamFacts): string[] {
  const before = bestThree(ours);
  const after = bestThree([...ours, candidate]);
  const points =
    candidate.mean === null
      ? null
      : after > before
        ? `+${after - before} pts to our best 3 (now ${before}, would be ${after})`
        : `No change to our best 3 (now ${before})`;
  const lines: string[] = [];
  if (points && after > before) lines.push(points);
  if (candidate.incidents)
    lines.push(`${describe(candidate.incidents)}: check before picking`);
  if (reliable(candidate) && candidate.l3) {
    const have = ours.filter(reliable).length;
    lines.push(
      `Reliable L3 climb (${candidate.l3.successes} of ${candidate.l3.attempts}); we have ${have} L3 ${have === 1 ? "climber" : "climbers"}`,
    );
  } else if (
    candidate.l3 &&
    candidate.l3.attempts > 0 &&
    candidate.l3.successes === 0
  ) {
    lines.push(`No successful L3 climb (0 of ${candidate.l3.attempts})`);
  }
  if (candidate.defender)
    lines.push(
      ours.some((t) => t.defender)
        ? "Plays defense (we already have a defender)"
        : "Plays defense: none of ours does",
    );
  const bestAuto = Math.max(0, ...ours.map((t) => t.auto ?? 0));
  if (candidate.auto && candidate.auto > bestAuto)
    lines.push(
      `Best auto on the alliance (${candidate.auto.toFixed(1)} vs our best ${bestAuto.toFixed(1)})`,
    );
  return points && after <= before
    ? [...lines.slice(0, 3), points]
    : lines.slice(0, 4);
}
