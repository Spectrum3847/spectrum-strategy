import { isLead } from "../auth/roles";
import type { ShiftRosterEntry } from "../scout/credit";

export const canEditShifts = isLead;

export function parseNames(pasted: string): string[] {
  const seen = new Set<string>();
  const names: string[] = [];
  for (const part of pasted.split(/[\n\r,;\t]+/)) {
    const name = part.trim();
    if (name === "" || seen.has(name.toLowerCase())) continue;
    seen.add(name.toLowerCase());
    names.push(name);
  }
  return names;
}

export interface ProfileName {
  uid: string;
  displayName: string;
}

export interface ResolvedRoster {
  roster: ShiftRosterEntry[];
  ambiguous: string[];
  unmatched: string[];
}

export function resolveRoster(
  names: string[],
  profiles: ProfileName[] | null,
): ResolvedRoster {
  const keyOf = (s: string) => s.trim().toLowerCase();
  const byName = new Map<string, string[]>();
  for (const p of profiles ?? []) {
    if (p.displayName === "") continue;
    byName.set(keyOf(p.displayName), [
      ...(byName.get(keyOf(p.displayName)) ?? []),
      p.uid,
    ]);
  }
  const ambiguous: string[] = [];
  const unmatched: string[] = [];
  const roster = names.map((name) => {
    const uids = byName.get(keyOf(name)) ?? [];
    if (uids.length > 1) ambiguous.push(name);
    else if (uids.length === 0 && profiles) unmatched.push(name);
    return { uid: uids.length === 1 ? (uids[0] ?? "") : "", name };
  });
  return { roster, ambiguous, unmatched };
}
