export const allRoles = [
  "viewer",
  "scouter",
  "strategy",
  "admin",
  "developer",
  "mentor",
] as const;
export type Role = (typeof allRoles)[number];

export interface UserProfile {
  uid: string;
  displayName: string;
  roles: Role[];
  canonicalUid: string | null;
}

const isRole = (value: unknown): value is Role =>
  typeof value === "string" && (allRoles as readonly string[]).includes(value);

const unique = (roles: Role[]) => [...new Set(roles)];

export function parseProfile(
  uid: string,
  data: Record<string, unknown>,
): UserProfile {
  let roles: Role[];
  if (Array.isArray(data.roles) && data.roles.length > 0) {
    const parsed = unique(data.roles.filter(isRole));
    roles = parsed.length > 0 ? parsed : ["viewer"];
  } else {
    roles = [isRole(data.role) ? data.role : "viewer"];
  }
  const canonical = data.canonicalUid;
  return {
    uid,
    displayName: typeof data.displayName === "string" ? data.displayName : "",
    roles,
    canonicalUid:
      typeof canonical === "string" && canonical !== "" ? canonical : null,
  };
}

const leadRoles: Role[] = ["strategy", "admin", "developer"];
const writerRoles: Role[] = ["scouter", ...leadRoles];

export const canDeleteEntry = (
  roles: Role[],
  uid: string | null,
  authorUid: string,
) => canWrite(roles) && (isLead(roles) || (uid !== null && uid === authorUid));

export const hasAppAccess = (roles: Role[]) =>
  roles.some((r) => r !== "viewer");
export const isLead = (roles: Role[]) =>
  roles.some((r) => leadRoles.includes(r));
export const canWrite = (roles: Role[]) =>
  roles.some((r) => writerRoles.includes(r));
export const isMentor = (roles: Role[]) => roles.includes("mentor");
export const isMentorOnly = (roles: Role[]) =>
  isMentor(roles) && !canWrite(roles);
export const readsLeadPages = (roles: Role[]) =>
  isLead(roles) || isMentor(roles);

export const canOpenTeamPage = readsLeadPages;
export const canOpenMatchPage = readsLeadPages;

const scouterPaths = ["/", "/scout", "/schedule", "/settings", "/help"];

function under(pathname: string, base: string): boolean {
  if (base === "/") return pathname === "/";
  return pathname === base || pathname.startsWith(`${base}/`);
}

const mentorPaths = [
  "/",
  "/database",
  "/teams",
  "/matches",
  "/picks",
  "/schedule",
  "/settings",
  "/help",
];

const adminPaths = ["/users"];

const developerPaths = ["/usage"];

const leadPaths = ["/scout/accuracy"];

const trimmed = (pathname: string) =>
  pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;

export const needsAdmin = (pathname: string) =>
  adminPaths.some((base) => under(trimmed(pathname), base));

export const needsDeveloper = (pathname: string) =>
  developerPaths.some((base) => under(trimmed(pathname), base));

export function canOpenPath(roles: Role[], pathname: string): boolean {
  if (needsAdmin(pathname)) return roles.includes("admin");
  if (needsDeveloper(pathname)) return roles.includes("developer");
  if (isLead(roles)) return true;
  if (!hasAppAccess(roles)) return false;
  const path = trimmed(pathname);
  const asScouter =
    roles.includes("scouter") &&
    !leadPaths.some((base) => under(path, base)) &&
    scouterPaths.some((base) => under(path, base));
  return (
    asScouter || (isMentor(roles) && mentorPaths.some((b) => under(path, b)))
  );
}

export function landingFor(
  roles: Role[],
  nextMatchKey: string | null,
): string | null {
  if (!isMentorOnly(roles) || nextMatchKey === null) return null;
  return `/matches/${encodeURIComponent(nextMatchKey)}?tab=brief`;
}

export function identityName(
  profile: UserProfile,
  canonicalName: string | null,
  authName: string | null,
): string {
  if (canonicalName) return canonicalName;
  return profile.displayName || authName || "";
}

export function newProfileDoc(
  uid: string,
  displayName: string,
  email: string | null,
  now: Date,
): Record<string, unknown> {
  return {
    uid,
    displayName: displayName.slice(0, 256),
    ...(email ? { email } : {}),
    roles: ["scouter"],
    createdAt: now.toISOString(),
  };
}

export type ProfileRead =
  | { kind: "profile"; profile: UserProfile }
  | { kind: "missing" }
  | { kind: "unknown" }
  | { kind: "error" };

export function readProfile(
  uid: string,
  snap: {
    exists: boolean;
    fromCache: boolean;
    data: Record<string, unknown> | undefined;
  },
): ProfileRead {
  if (snap.exists && snap.data) {
    return { kind: "profile", profile: parseProfile(uid, snap.data) };
  }
  return snap.fromCache ? { kind: "unknown" } : { kind: "missing" };
}

export type RolesState =
  | { status: "loading" }
  | { status: "signed-out" }
  | { status: "unavailable" }
  | {
      status: "ready";
      uid: string;
      roles: Role[];
      displayName: string;
      identityUids: string[];
    };

export interface RolesInput {
  auth: "loading" | "signing-in" | "signed-in" | "signed-out";
  uid: string | null;
  authName: string | null;
  read: ProfileRead | null;
  canonicalName: string | null;
  stalled: boolean;
  online: boolean;
}

export function rolesState(input: RolesInput): RolesState {
  if (input.auth === "signed-out") return { status: "signed-out" };
  if (input.auth !== "signed-in" || input.uid === null) {
    return { status: "loading" };
  }
  const { read } = input;
  if (read === null) {
    return input.stalled ? { status: "unavailable" } : { status: "loading" };
  }
  if (read.kind === "error") return { status: "unavailable" };
  if (read.kind === "unknown") {
    return input.stalled || !input.online
      ? { status: "unavailable" }
      : { status: "loading" };
  }
  if (read.kind === "missing") {
    return {
      status: "ready",
      uid: input.uid,
      roles: ["scouter"],
      displayName: input.authName ?? "",
      identityUids: [input.uid],
    };
  }
  const { profile } = read;
  return {
    status: "ready",
    uid: input.uid,
    roles: profile.roles,
    displayName: identityName(profile, input.canonicalName, input.authName),
    identityUids: profile.canonicalUid
      ? [input.uid, profile.canonicalUid]
      : [input.uid],
  };
}
