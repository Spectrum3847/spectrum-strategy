import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { allRoles } from "../auth/roles";
import {
  linkCandidates,
  linkWrites,
  maxLinkedEmails,
  type ProfileWrite,
  profileUpdateKeys,
  renameWrite,
  rolesWrites,
  unlinkWrites,
} from "./edits";
import { type ManagedProfile, parseManaged } from "./profiles";

const rules = readFileSync(
  new URL("../../../firestore.rules", import.meta.url),
  "utf8",
);

function hasOnlyLists(fn: string): string[][] {
  const body = rules.slice(rules.indexOf(`function ${fn}(`));
  const end = body.indexOf("\n    }\n");
  return [...body.slice(0, end).matchAll(/hasOnly\(\[([^\]]*)\]\)/g)].map((m) =>
    [...(m[1] ?? "").matchAll(/'([^']+)'/g)].map((q) => q[1] ?? ""),
  );
}

const same = (a: unknown, b: unknown) =>
  JSON.stringify(a) === JSON.stringify(b);

function acceptedByRules(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): boolean {
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  const affected = [...keys].filter((k) => !same(before[k], after[k]));
  if (
    !affected.every((k) => (profileUpdateKeys as readonly string[]).includes(k))
  ) {
    return false;
  }
  const roles = after.roles;
  if (affected.includes("roles")) {
    if (!Array.isArray(roles)) return false;
    if (roles.length < 1 || roles.length > 5) return false;
    if (!roles.every((r) => (allRoles as readonly string[]).includes(r))) {
      return false;
    }
  }
  const name = after.displayName;
  if (
    "displayName" in after &&
    !(typeof name === "string" && name.length <= 256)
  ) {
    return false;
  }
  const email = after.email;
  if ("email" in after && !(typeof email === "string" && email.length <= 320)) {
    return false;
  }
  const canonical = after.canonicalUid;
  if (
    "canonicalUid" in after &&
    !(
      typeof canonical === "string" &&
      canonical.length > 0 &&
      canonical.length <= 128
    )
  ) {
    return false;
  }
  const linked = after.linkedEmails;
  if (
    "linkedEmails" in after &&
    !(Array.isArray(linked) && linked.length <= maxLinkedEmails)
  ) {
    return false;
  }
  return true;
}

const stored = (
  uid: string,
  extra: Record<string, unknown> = {},
): Record<string, unknown> => ({
  uid,
  displayName: `Member ${uid}`,
  email: `${uid}@example.test`,
  roles: ["scouter"],
  createdAt: "2027-01-01T00:00:00.000Z",
  ...extra,
});

const profile = (uid: string, extra: Record<string, unknown> = {}) => {
  const data = stored(uid, extra);
  return parseManaged(uid, data);
};

const own = profile("admin1", { roles: ["admin"] });
const a = profile("a1");
const b = profile("b1", {
  roles: ["strategy"],
  linkedEmails: ["old@example.test"],
});

const accepted = (w: ProfileWrite, roster: ManagedProfile[]) => {
  const before = roster.find((p) => p.uid === w.uid)?.raw ?? {};
  return acceptedByRules(before, w.doc);
};

describe("the rules this screen is written against", () => {
  it("lets an update touch exactly the keys the screen writes", () => {
    expect(hasOnlyLists("isValidProfileUpdate")[0]).toEqual([
      ...profileUpdateKeys,
    ]);
  });

  it("allows exactly the role set the app has", () => {
    expect(hasOnlyLists("isValidProfileUpdate")[1]).toEqual([...allRoles]);
    expect(hasOnlyLists("isValidAdminProfileCreate")[1]).toEqual([...allRoles]);
  });

  it("creates a missing profile from {roles} alone", () => {
    expect(hasOnlyLists("isValidAdminProfileCreate")[0]).toEqual(["roles"]);
  });

  it("caps linked addresses where the screen does", () => {
    expect(rules).toContain(`data.linkedEmails.size() <= ${maxLinkedEmails}`);
  });
});

describe("renameWrite", () => {
  it("writes the stored document with only the name changed", () => {
    const w = renameWrite(a, "  New Name ", own.uid);
    expect(w.uid).toBe("a1");
    expect(w.doc).toEqual({ ...a.raw, displayName: "New Name" });
    expect(accepted(w, [a])).toBe(true);
  });

  it("refuses an empty name and the admin's own profile", () => {
    expect(() => renameWrite(a, "   ", own.uid)).toThrow(/empty/);
    expect(() => renameWrite(own, "X", own.uid)).toThrow(/own profile/);
  });

  it("keeps a legacy role field instead of dropping it", () => {
    const legacy = profile("l1", { role: "scouter" });
    const w = renameWrite(legacy, "Legacy", own.uid);
    expect(w.doc.role).toBe("scouter");
    expect(accepted(w, [legacy])).toBe(true);
  });
});

describe("rolesWrites", () => {
  it("writes the role array in app order and only that", () => {
    const [w, ...rest] = rolesWrites(a, ["strategy", "scouter"], [a], own.uid);
    expect(rest).toEqual([]);
    expect(w?.doc).toEqual({ ...a.raw, roles: ["scouter", "strategy"] });
    expect(accepted(w as ProfileWrite, [a])).toBe(true);
  });

  it("saves viewer when no role is picked", () => {
    const [w] = rolesWrites(a, [], [a], own.uid);
    expect(w?.doc.roles).toEqual(["viewer"]);
  });

  it("covers the primary and every linked secondary, never the admin", () => {
    const second = profile("s1", { canonicalUid: "a1", roles: ["scouter"] });
    const mine = profile("admin1", { canonicalUid: "a1", roles: ["admin"] });
    const roster = [a, second, mine];
    const writes = rolesWrites(second, ["admin"], roster, "admin1");
    expect(writes.map((w) => w.uid).sort()).toEqual(["a1", "s1"]);
    for (const w of writes) expect(accepted(w, roster)).toBe(true);
  });

  it("never writes a primary that is not loaded, so it cannot be erased", () => {
    const orphan = profile("o1", { canonicalUid: "gone" });
    const writes = rolesWrites(orphan, ["scouter"], [orphan], own.uid);
    expect(writes.map((w) => w.uid)).toEqual(["o1"]);
    expect(writes[0]?.doc).toEqual({ ...orphan.raw, roles: ["scouter"] });
  });

  it("refuses the admin's own profile", () => {
    expect(() => rolesWrites(own, ["viewer"], [own], own.uid)).toThrow(
      /own profile/,
    );
  });
});

describe("linkWrites", () => {
  const roster = [a, b];

  it("points the secondary at the primary with its roles, and lists the address", () => {
    const [secondary, primary] = linkWrites(a, b, own.uid);
    expect(secondary?.doc).toEqual({
      ...a.raw,
      canonicalUid: "b1",
      roles: ["strategy"],
    });
    expect(primary?.doc).toEqual({
      ...b.raw,
      linkedEmails: ["old@example.test", "a1@example.test"],
    });
    for (const w of [secondary, primary]) {
      expect(accepted(w as ProfileWrite, roster)).toBe(true);
    }
  });

  it("does not list an address twice", () => {
    const again = profile("b1", { linkedEmails: ["a1@example.test"] });
    const [, primary] = linkWrites(a, again, own.uid);
    expect(primary?.doc.linkedEmails).toEqual(["a1@example.test"]);
  });

  it("refuses invalid links, and an eleventh address", () => {
    expect(() => linkWrites(a, a, own.uid)).toThrow(/itself/);
    const secondary = profile("c1", { canonicalUid: "b1" });
    expect(() => linkWrites(a, secondary, own.uid)).toThrow(/primary/);
    const noEmail = profile("d1", { email: "" });
    expect(() => linkWrites(noEmail, b, own.uid)).toThrow(/email/);
    const full = profile("f1", {
      linkedEmails: Array.from(
        { length: maxLinkedEmails },
        (_, i) => `${i}@x.test`,
      ),
    });
    expect(() => linkWrites(a, full, own.uid)).toThrow(/at most/);
    expect(() => linkWrites(a, own, own.uid)).toThrow(/own profile/);
  });

  it("refuses to move a linked account straight to a new primary", () => {
    const linked = profile("a1", { canonicalUid: "z1" });
    expect(() => linkWrites(linked, b, own.uid)).toThrow(/Unlink it first/);
    const same = profile("a1", { canonicalUid: "b1" });
    expect(() => linkWrites(same, b, own.uid)).not.toThrow();
  });

  it("offers primaries only, not itself or the admin", () => {
    const secondary = profile("c1", { canonicalUid: "b1" });
    const list = linkCandidates(a, [own, a, b, secondary], own.uid);
    expect(list.map((p) => p.uid)).toEqual(["b1"]);
  });
});

describe("unlinkWrites", () => {
  const secondary = profile("s1", { canonicalUid: "b1", roles: ["strategy"] });
  const primary = profile("b1", {
    roles: ["strategy"],
    linkedEmails: ["s1@example.test", "other@example.test"],
  });
  const roster = [secondary, primary];

  it("drops canonicalUid, sets viewer and removes the address", () => {
    const [sec, prim] = unlinkWrites(secondary, primary, own.uid);
    expect(sec?.doc).toEqual({ ...stored("s1"), roles: ["viewer"] });
    expect(sec?.doc).not.toHaveProperty("canonicalUid");
    expect(prim?.doc).toEqual({
      ...primary.raw,
      linkedEmails: ["other@example.test"],
    });
    for (const w of [sec, prim]) {
      expect(accepted(w as ProfileWrite, roster)).toBe(true);
    }
  });

  it("leaves a primary that is missing or does not list the address", () => {
    expect(unlinkWrites(secondary, null, own.uid)).toHaveLength(1);
    const unlisted = profile("b1", { linkedEmails: [] });
    expect(unlinkWrites(secondary, unlisted, own.uid)).toHaveLength(1);
  });

  it("refuses an account that is not linked and one linked to the admin", () => {
    expect(() => unlinkWrites(a, null, own.uid)).toThrow(/not linked/);
    expect(() => unlinkWrites(secondary, own, own.uid)).toThrow(/own profile/);
  });
});

describe("the rules checker used above", () => {
  it("rejects a write that changes a key the rules lock", () => {
    expect(acceptedByRules(a.raw, { ...a.raw, uid: "other" })).toBe(false);
    expect(acceptedByRules(a.raw, { ...a.raw, createdAt: "x" })).toBe(false);
    const { createdAt: _gone, ...without } = a.raw;
    expect(acceptedByRules(a.raw, without)).toBe(false);
    expect(acceptedByRules(a.raw, { ...a.raw, roles: ["wizard"] })).toBe(false);
  });
});
