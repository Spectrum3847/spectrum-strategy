import { allRoles, parseProfile, type Role } from "../auth/roles";

export interface ManagedProfile {
  uid: string;
  displayName: string;
  email: string | null;
  roles: Role[];
  canonicalUid: string | null;
  linkedEmails: string[];
  raw: Record<string, unknown>;
}

export function parseManaged(
  uid: string,
  data: Record<string, unknown>,
): ManagedProfile {
  const base = parseProfile(uid, data);
  const emails = Array.isArray(data.linkedEmails)
    ? data.linkedEmails.filter((e): e is string => typeof e === "string")
    : [];
  return {
    uid,
    displayName: base.displayName,
    email:
      typeof data.email === "string" && data.email !== "" ? data.email : null,
    roles: base.roles,
    canonicalUid: base.canonicalUid,
    linkedEmails: emails,
    raw: data,
  };
}

export function byDisplayName(a: ManagedProfile, b: ManagedProfile): number {
  const byName = a.displayName
    .toLowerCase()
    .localeCompare(b.displayName.toLowerCase());
  return byName !== 0 ? byName : a.uid.localeCompare(b.uid);
}

export const roleLabel: Record<Role, string> = {
  viewer: "Viewer",
  scouter: "Scouter",
  strategy: "Strategist",
  admin: "Admin",
  developer: "Developer",
  mentor: "Mentor",
};

export const rolesText = (roles: Role[]) =>
  roles
    .map((r) => roleLabel[r])
    .sort()
    .join(", ");

export function matchesSearch(p: ManagedProfile, search: string): boolean {
  const q = search.trim().toLowerCase();
  if (q === "") return true;
  return (
    p.displayName.toLowerCase().includes(q) ||
    (p.email ?? "").toLowerCase().includes(q)
  );
}

export const isLinkedSecondary = (p: ManagedProfile) => p.canonicalUid !== null;

export function normalizeRoles(roles: Iterable<Role>): Role[] {
  const picked = new Set(roles);
  const ordered = allRoles.filter((r) => picked.has(r));
  return ordered.length > 0 ? ordered : ["viewer"];
}

export type UsersView =
  | { kind: "loading" }
  | { kind: "refused" }
  | { kind: "failed" }
  | { kind: "nothing-cached" }
  | { kind: "empty" }
  | { kind: "list"; source: "server" | "cache" };

export interface ProfilesSeen {
  ready: boolean;
  failed: boolean;
  code: string | null;
  fromCache: boolean;
  count: number;
}

export function usersView(seen: ProfilesSeen): UsersView {
  if (seen.failed) {
    return seen.code?.replace(/^firestore\//, "") === "permission-denied"
      ? { kind: "refused" }
      : { kind: "failed" };
  }
  if (!seen.ready) return { kind: "loading" };
  if (seen.count === 0) {
    return seen.fromCache ? { kind: "nothing-cached" } : { kind: "empty" };
  }
  return { kind: "list", source: seen.fromCache ? "cache" : "server" };
}
