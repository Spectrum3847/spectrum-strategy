import { Timestamp } from "firebase/firestore";

export const defaultTierNames = [
  "1st pick",
  "2nd pick",
  "Defense/role",
  "Backup",
];

export const maxTeams = 64;
export const maxTiers = 12;
export const maxDnp = 64;
export const maxName = 128;
export const maxReason = 200;
const maxTeamNumber = 99999;

export interface PickTier {
  name: string;
  teams: number[];
}

export interface DoNotPick {
  team: number;
  reason: string;
}

export interface PickList {
  id: string;
  name: string;
  teamNumbers: number[];
  tiers: PickTier[];
  dnp: DoNotPick[];
  authorUid: string;
  authorDisplayName: string;
  updatedMs: number;
}

type Raw = Record<string, unknown>;
const isRecord = (v: unknown): v is Raw =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown) => (typeof v === "string" ? v : "");

const teamsFrom = (raw: unknown): number[] =>
  Array.isArray(raw)
    ? raw
        .filter((n): n is number => typeof n === "number")
        .map(Math.trunc)
        .filter((n) => n >= 1 && n <= maxTeamNumber)
    : [];

export function parsePickList(id: string, data: Raw): PickList {
  const tiers: PickTier[] = [];
  if (Array.isArray(data.tiers)) {
    for (const raw of data.tiers) {
      if (isRecord(raw)) {
        tiers.push({ name: str(raw.name), teams: teamsFrom(raw.teams) });
      }
    }
  }
  const dnp: DoNotPick[] = [];
  if (Array.isArray(data.dnp)) {
    for (const raw of data.dnp) {
      if (
        isRecord(raw) &&
        typeof raw.team === "number" &&
        raw.team >= 1 &&
        raw.team <= maxTeamNumber
      ) {
        dnp.push({ team: Math.trunc(raw.team), reason: str(raw.reason) });
      }
    }
  }
  const parsed = Date.parse(str(data.updatedAt));
  return {
    id,
    name: str(data.name),
    teamNumbers: teamsFrom(data.teamNumbers),
    tiers,
    dnp,
    authorUid: str(data.authorUid),
    authorDisplayName: str(data.authorDisplayName),
    updatedMs:
      data.updatedAtTs instanceof Timestamp
        ? data.updatedAtTs.toMillis()
        : Number.isNaN(parsed)
          ? 0
          : parsed,
  };
}

export interface Layout {
  tiers: PickTier[];
  dnp: DoNotPick[];
}

export function layoutOf(list: PickList): Layout {
  const base =
    list.tiers.length > 0
      ? list.tiers
      : defaultTierNames.map((name) => ({ name, teams: [] as number[] }));
  const wanted = new Set(list.teamNumbers);
  const seen = new Set<number>();
  const tiers = base.map((tier) => ({
    name: tier.name,
    teams: tier.teams.filter((t) => {
      if (!wanted.has(t) || seen.has(t)) return false;
      seen.add(t);
      return true;
    }),
  }));
  const extra = list.teamNumbers.filter((t) => {
    if (seen.has(t)) return false;
    seen.add(t);
    return true;
  });
  if (extra.length > 0 && tiers[0]) tiers[0].teams.push(...extra);
  return {
    tiers,
    dnp: list.dnp.filter((d) => !wanted.has(d.team)),
  };
}

export const flatten = (tiers: PickTier[]) => tiers.flatMap((t) => t.teams);

export const tierOf = (layout: Layout, team: number): number | null => {
  const at = layout.tiers.findIndex((t) => t.teams.includes(team));
  return at < 0 ? null : at;
};

export const isDnp = (layout: Layout, team: number) =>
  layout.dnp.some((d) => d.team === team);

export const rankedCount = (layout: Layout) => flatten(layout.tiers).length;

function without(layout: Layout, team: number): Layout {
  return {
    tiers: layout.tiers.map((t) => ({
      ...t,
      teams: t.teams.filter((x) => x !== team),
    })),
    dnp: layout.dnp.filter((d) => d.team !== team),
  };
}

export function placeTeam(
  layout: Layout,
  team: number,
  tier: number,
  index?: number,
): Layout {
  const at = Math.min(Math.max(tier, 0), layout.tiers.length - 1);
  if (tierOf(layout, team) === null && rankedCount(layout) >= maxTeams) {
    return layout;
  }
  const next = without(layout, team);
  const target = next.tiers[at];
  if (!target) return layout;
  const teams = [...target.teams];
  teams.splice(index === undefined ? teams.length : index, 0, team);
  return {
    ...next,
    tiers: next.tiers.map((t, i) => (i === at ? { ...t, teams } : t)),
  };
}

export const removeTeam = without;

export function markDnp(layout: Layout, team: number, reason: string): Layout {
  const next = without(layout, team);
  if (next.dnp.length >= maxDnp) return layout;
  return {
    ...next,
    dnp: [...next.dnp, { team, reason: reason.trim().slice(0, maxReason) }],
  };
}

export function setReason(
  layout: Layout,
  team: number,
  reason: string,
): Layout {
  return {
    ...layout,
    dnp: layout.dnp.map((d) =>
      d.team === team ? { ...d, reason: reason.trim().slice(0, maxReason) } : d,
    ),
  };
}

type Row = { header: number } | { team: number; tier: number };

function rowsOf(layout: Layout): Row[] {
  return layout.tiers.flatMap((tier, i): Row[] => [
    { header: i },
    ...tier.teams.map((team) => ({ team, tier: i })),
  ]);
}

export function moveBy(layout: Layout, team: number, delta: -1 | 1): Layout {
  const rows = rowsOf(layout);
  const from = rows.findIndex((r) => "team" in r && r.team === team);
  const target = from + delta;
  if (from < 0 || target < 0 || target >= rows.length) return layout;
  const rest = rows.filter((_, i) => i !== from);
  let tier = 0;
  let position = 0;
  for (const row of rest.slice(0, target)) {
    if ("header" in row) {
      tier = row.header;
      position = 0;
    } else {
      position += 1;
    }
  }
  return placeTeam(layout, team, tier, position);
}

export function renameTier(layout: Layout, tier: number, name: string): Layout {
  const trimmed = name.trim().slice(0, maxName);
  if (trimmed === "") return layout;
  return {
    ...layout,
    tiers: layout.tiers.map((t, i) =>
      i === tier ? { ...t, name: trimmed } : t,
    ),
  };
}

export function addTier(layout: Layout, name: string): Layout {
  const trimmed = name.trim().slice(0, maxName);
  if (trimmed === "" || layout.tiers.length >= maxTiers) return layout;
  return { ...layout, tiers: [...layout.tiers, { name: trimmed, teams: [] }] };
}

export function removeTier(layout: Layout, tier: number): Layout {
  const found = layout.tiers[tier];
  if (layout.tiers.length < 2 || !found || found.teams.length > 0) {
    return layout;
  }
  return { ...layout, tiers: layout.tiers.filter((_, i) => i !== tier) };
}

export interface Author {
  uid: string;
  displayName: string;
}

export function newList(name: string, author: Author, nowMs: number): PickList {
  return {
    id: crypto.randomUUID(),
    name: name.trim().slice(0, maxName) || "Untitled list",
    teamNumbers: [],
    tiers: [],
    dnp: [],
    authorUid: author.uid,
    authorDisplayName: author.displayName.slice(0, 128),
    updatedMs: nowMs,
  };
}

const stamped = (prev: PickList, nowMs: number) => ({
  updatedMs: Math.max(nowMs, prev.updatedMs),
});

export function applyLayout(
  prev: PickList,
  layout: Layout,
  nowMs: number,
): PickList {
  return {
    ...prev,
    tiers: layout.tiers,
    dnp: layout.dnp,
    teamNumbers: flatten(layout.tiers),
    ...stamped(prev, nowMs),
  };
}

export function applyName(
  prev: PickList,
  name: string,
  nowMs: number,
): PickList {
  const trimmed = name.trim().slice(0, maxName);
  return {
    ...prev,
    name: trimmed === "" ? prev.name : trimmed,
    ...stamped(prev, nowMs),
  };
}

export function pickListDoc(list: PickList): Raw {
  return {
    id: list.id,
    name: list.name,
    teamNumbers: list.teamNumbers,
    updatedAt: new Date(list.updatedMs).toISOString(),
    authorUid: list.authorUid,
    authorDisplayName: list.authorDisplayName,
    ...(list.tiers.length > 0
      ? {
          tiers: list.tiers.map((t) => ({ name: t.name, teams: t.teams })),
        }
      : {}),
    ...(list.dnp.length > 0
      ? { dnp: list.dnp.map((d) => ({ team: d.team, reason: d.reason })) }
      : {}),
    updatedAtTs: Timestamp.fromMillis(list.updatedMs),
  };
}

export function refusalNote(sentMs: number | null, shownMs: number): string {
  if (sentMs !== null && shownMs > sentMs) {
    return "Another lead saved a newer version first, so this change was refused. The list now shows theirs.";
  }
  return "The database refused this change. Check that your role still allows editing pick lists.";
}
