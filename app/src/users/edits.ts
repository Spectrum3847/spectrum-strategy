import type { Role } from "../auth/roles";
import {
  isLinkedSecondary,
  type ManagedProfile,
  normalizeRoles,
} from "./profiles";

export const profileUpdateKeys = [
  "displayName",
  "email",
  "roles",
  "canonicalUid",
  "linkedEmails",
] as const;

export const maxNameLength = 64;
export const maxLinkedEmails = 10;

export interface ProfileWrite {
  uid: string;
  doc: Record<string, unknown>;
  label: string;
}

export const profilePath = (uid: string) => `userProfiles/${uid}`;

const nameOf = (p: ManagedProfile) => p.displayName || p.email || p.uid;

function assertNotOwn(target: ManagedProfile, ownUid: string) {
  if (target.uid === ownUid) {
    throw new Error("You cannot edit your own profile.");
  }
}

export function renameWrite(
  target: ManagedProfile,
  name: string,
  ownUid: string,
): ProfileWrite {
  assertNotOwn(target, ownUid);
  const trimmed = name.trim().slice(0, maxNameLength);
  if (trimmed === "") throw new Error("A display name cannot be empty.");
  return {
    uid: target.uid,
    doc: { ...target.raw, displayName: trimmed },
    label: `Name for ${nameOf(target)}`,
  };
}

export function rolesWrites(
  target: ManagedProfile,
  roles: Iterable<Role>,
  roster: ManagedProfile[],
  ownUid: string,
): ProfileWrite[] {
  assertNotOwn(target, ownUid);
  const next = normalizeRoles(roles);
  const primaryUid = target.canonicalUid ?? target.uid;
  const uids = new Set([
    primaryUid,
    target.uid,
    ...roster.filter((p) => p.canonicalUid === primaryUid).map((p) => p.uid),
  ]);
  uids.delete(ownUid);
  return [...uids].flatMap((uid) => {
    const known =
      uid === target.uid ? target : roster.find((p) => p.uid === uid);
    if (!known) return [];
    return [
      {
        uid,
        doc: { ...known.raw, roles: next },
        label: `Roles for ${nameOf(known)}`,
      },
    ];
  });
}

export function linkCandidates(
  secondary: ManagedProfile,
  roster: ManagedProfile[],
  ownUid: string,
): ManagedProfile[] {
  return roster.filter(
    (p) => p.uid !== secondary.uid && p.uid !== ownUid && !isLinkedSecondary(p),
  );
}

export function linkWrites(
  secondary: ManagedProfile,
  primary: ManagedProfile,
  ownUid: string,
): ProfileWrite[] {
  assertNotOwn(secondary, ownUid);
  assertNotOwn(primary, ownUid);
  if (secondary.uid === primary.uid) {
    throw new Error("An account cannot be linked to itself.");
  }
  if (isLinkedSecondary(primary)) {
    throw new Error(
      "That account is already linked to another one. Link to the primary.",
    );
  }
  if (isLinkedSecondary(secondary) && secondary.canonicalUid !== primary.uid) {
    throw new Error(
      "That account is linked to another primary. Unlink it first.",
    );
  }
  const email = secondary.email;
  if (!email) {
    throw new Error("The account being linked has no email address.");
  }
  const emails = primary.linkedEmails.includes(email)
    ? primary.linkedEmails
    : [...primary.linkedEmails, email];
  if (emails.length > maxLinkedEmails) {
    throw new Error(
      `A primary account can list at most ${maxLinkedEmails} linked addresses.`,
    );
  }
  return [
    {
      uid: secondary.uid,
      doc: {
        ...secondary.raw,
        canonicalUid: primary.uid,
        roles: normalizeRoles(primary.roles),
      },
      label: `Link ${nameOf(secondary)}`,
    },
    {
      uid: primary.uid,
      doc: { ...primary.raw, linkedEmails: emails },
      label: `Linked address for ${nameOf(primary)}`,
    },
  ];
}

export function unlinkWrites(
  secondary: ManagedProfile,
  primary: ManagedProfile | null,
  ownUid: string,
): ProfileWrite[] {
  assertNotOwn(secondary, ownUid);
  if (!isLinkedSecondary(secondary)) {
    throw new Error("That account is not linked to another one.");
  }
  if (primary) assertNotOwn(primary, ownUid);
  const { canonicalUid: _removed, ...rest } = secondary.raw;
  const writes: ProfileWrite[] = [
    {
      uid: secondary.uid,
      doc: { ...rest, roles: ["viewer"] },
      label: `Unlink ${nameOf(secondary)}`,
    },
  ];
  if (primary && secondary.email) {
    const emails = primary.linkedEmails.filter((e) => e !== secondary.email);
    if (emails.length !== primary.linkedEmails.length) {
      writes.push({
        uid: primary.uid,
        doc: { ...primary.raw, linkedEmails: emails },
        label: `Linked address for ${nameOf(primary)}`,
      });
    }
  }
  return writes;
}
