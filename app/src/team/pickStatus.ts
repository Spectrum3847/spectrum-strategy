import {
  flatten,
  isDnp,
  layoutOf,
  type PickList,
  tierOf,
} from "../picks/pickList";

export function pickStatus(list: PickList, team: number): string {
  const layout = layoutOf(list);
  const reason = layout.dnp.find((d) => d.team === team)?.reason;
  if (isDnp(layout, team)) {
    return `Do not pick: ${reason || "no reason given"} (${list.name})`;
  }
  const tier = tierOf(layout, team);
  if (tier === null) return `Not on ${list.name}`;
  const rank = flatten(layout.tiers).indexOf(team) + 1;
  const name = layout.tiers[tier]?.name ?? "";
  return `Tier ${tier + 1}${name ? ` (${name})` : ""}, #${rank} on ${list.name}`;
}
