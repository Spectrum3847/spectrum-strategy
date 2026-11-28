import { describe, expect, it } from "vitest";
import {
  canDeleteEntry,
  canOpenMatchPage,
  canOpenPath,
  canOpenTeamPage,
  canWrite,
  hasAppAccess,
  identityName,
  isLead,
  isMentorOnly,
  landingFor,
  newProfileDoc,
  parseProfile,
  type RolesInput,
  readProfile,
  rolesState,
} from "./roles";

describe("parseProfile", () => {
  it("reads the roles array and skips unknown strings", () => {
    const p = parseProfile("u1", {
      roles: ["scouter", "wizard", "scouter", "admin"],
      displayName: "Scout A",
    });
    expect(p.roles).toEqual(["scouter", "admin"]);
    expect(p.displayName).toBe("Scout A");
  });

  it("falls back to viewer when no role in the array is known", () => {
    expect(parseProfile("u1", { roles: ["wizard"] }).roles).toEqual(["viewer"]);
  });

  it("reads the legacy single role only when the array is empty or absent", () => {
    expect(parseProfile("u1", { role: "strategy" }).roles).toEqual([
      "strategy",
    ]);
    expect(parseProfile("u1", { roles: [], role: "admin" }).roles).toEqual([
      "admin",
    ]);
    expect(parseProfile("u1", { role: 7 }).roles).toEqual(["viewer"]);
    expect(parseProfile("u1", {}).roles).toEqual(["viewer"]);
  });

  it("keeps canonicalUid only when it is a non-empty string", () => {
    expect(parseProfile("u1", { canonicalUid: "p1" }).canonicalUid).toBe("p1");
    expect(parseProfile("u1", { canonicalUid: "" }).canonicalUid).toBeNull();
    expect(parseProfile("u1", {}).canonicalUid).toBeNull();
  });
});

describe("role helpers", () => {
  it("treats viewer as no access and the other roles as members", () => {
    expect(hasAppAccess(["viewer"])).toBe(false);
    expect(hasAppAccess(["scouter"])).toBe(true);
    expect(hasAppAccess(["viewer", "scouter"])).toBe(true);
  });

  it("names strategy, admin and developer as leads", () => {
    expect(isLead(["scouter"])).toBe(false);
    for (const role of ["strategy", "admin", "developer"] as const) {
      expect(isLead([role])).toBe(true);
    }
    expect(isLead(["scouter", "admin"])).toBe(true);
    expect(canOpenTeamPage(["scouter"])).toBe(false);
  });
});

describe("mentor role", () => {
  it("reads roles, with a mentor kept beside the others", () => {
    expect(parseProfile("u1", { roles: ["mentor"] }).roles).toEqual(["mentor"]);
    expect(parseProfile("u1", { role: "mentor" }).roles).toEqual(["mentor"]);
    expect(parseProfile("u1", { roles: ["mentor", "scouter"] }).roles).toEqual([
      "mentor",
      "scouter",
    ]);
  });

  it("is a member that reads lead pages and writes nothing", () => {
    expect(hasAppAccess(["mentor"])).toBe(true);
    expect(isLead(["mentor"])).toBe(false);
    expect(canWrite(["mentor"])).toBe(false);
    expect(canOpenTeamPage(["mentor"])).toBe(true);
    expect(canOpenMatchPage(["mentor"])).toBe(true);
    expect(canOpenTeamPage(["scouter"])).toBe(false);
  });

  it("writes again when another role writes", () => {
    expect(canWrite(["mentor", "scouter"])).toBe(true);
    expect(isMentorOnly(["mentor", "scouter"])).toBe(false);
    expect(isLead(["mentor", "strategy"])).toBe(true);
  });

  it("opens the pages that read and none that scout, count or manage", () => {
    for (const path of [
      "/",
      "/teams",
      "/teams/1111",
      "/teams/compare",
      "/matches/2027test_qm1",
      "/picks",
      "/picks/playoffs",
      "/schedule",
      "/settings",
      "/help",
      "/help/using-the-app",
    ]) {
      expect(canOpenPath(["mentor"], path), path).toBe(true);
    }
    for (const path of [
      "/scout",
      "/scout/scan",
      "/scout/shifts",
      "/scout/pit",
      "/scout/trex",
      "/scout/accuracy",
      "/users",
      "/teamsx",
    ]) {
      expect(canOpenPath(["mentor"], path), path).toBe(false);
    }
    expect(canOpenPath(["mentor"], "/database")).toBe(true);
  });

  it("gives a mentor who also scouts both sets of pages", () => {
    expect(canOpenPath(["mentor", "scouter"], "/scout")).toBe(true);
    expect(canOpenPath(["mentor", "scouter"], "/teams/1111")).toBe(true);
    expect(canOpenPath(["mentor", "scouter"], "/scout/accuracy")).toBe(false);
  });

  it("lands only a mentor with nothing that writes on the next brief", () => {
    expect(landingFor(["mentor"], "2027test_qm12")).toBe(
      "/matches/2027test_qm12?tab=brief",
    );
    expect(landingFor(["mentor"], null)).toBeNull();
    expect(landingFor(["mentor", "scouter"], "2027test_qm12")).toBeNull();
    expect(landingFor(["strategy"], "2027test_qm12")).toBeNull();
    expect(landingFor(["scouter"], "2027test_qm12")).toBeNull();
  });
});

describe("canOpenPath", () => {
  it("lets a scouter open the scouting surfaces, Now and Settings", () => {
    for (const path of [
      "/",
      "/scout",
      "/scout/scan",
      "/scout/pit",
      "/scout/pit/1111",
      "/scout/",
      "/schedule",
      "/settings",
      "/help",
      "/help/scouter-manual",
    ]) {
      expect(canOpenPath(["scouter"], path), path).toBe(true);
    }
  });

  it("keeps the scouter accuracy screen to leads", () => {
    for (const path of ["/scout/accuracy", "/scout/accuracy/"]) {
      expect(canOpenPath(["scouter"], path), path).toBe(false);
      for (const role of ["strategy", "admin", "developer"] as const) {
        expect(canOpenPath([role], path), `${role} ${path}`).toBe(true);
      }
    }
    expect(canOpenPath(["scouter"], "/scout/accuracyx")).toBe(true);
  });

  it("keeps the Database to leads", () => {
    expect(canOpenPath(["scouter"], "/database")).toBe(false);
    for (const role of ["strategy", "admin", "developer"] as const) {
      expect(canOpenPath([role], "/database"), role).toBe(true);
    }
  });

  it("keeps the AI chat to leads", () => {
    expect(canOpenPath(["scouter"], "/ai")).toBe(false);
    expect(canOpenPath(["mentor"], "/ai")).toBe(false);
    for (const role of ["strategy", "admin", "developer"] as const) {
      expect(canOpenPath([role], "/ai"), role).toBe(true);
    }
  });

  it("opens the Users page for admin only", () => {
    for (const path of ["/users", "/users/", "/users/u1"]) {
      expect(canOpenPath(["admin"], path), path).toBe(true);
      expect(canOpenPath(["scouter", "admin"], path), path).toBe(true);
      for (const role of ["strategy", "developer", "scouter"] as const) {
        expect(canOpenPath([role], path), `${role} ${path}`).toBe(false);
      }
    }
    expect(canOpenPath(["strategy"], "/usersx")).toBe(true);
  });

  it("keeps a scouter off every other page", () => {
    for (const path of [
      "/teams/1111",
      "/matches/2027test_qm1",
      "/picks",
      "/picks/playoffs",
      "/scouting",
      "/scoutx",
      "/settingsx",
    ]) {
      expect(canOpenPath(["scouter"], path), path).toBe(false);
    }
  });

  it("opens the usage page for the developer role only", () => {
    expect(canOpenPath(["developer"], "/usage")).toBe(true);
    for (const role of ["strategy", "admin", "scouter", "mentor"] as const) {
      expect(canOpenPath([role], "/usage"), role).toBe(false);
    }
  });

  it("opens everything for a lead and nothing for a viewer", () => {
    expect(canOpenPath(["strategy"], "/teams/1111")).toBe(true);
    expect(canOpenPath(["developer"], "/anything")).toBe(true);
    expect(canOpenPath(["viewer"], "/")).toBe(false);
  });
});

describe("identityName", () => {
  const profile = parseProfile("u1", { displayName: "Own Name" });
  it("prefers the primary account's name, then its own, then Google's", () => {
    expect(identityName(profile, "Primary Name", "Google")).toBe(
      "Primary Name",
    );
    expect(identityName(profile, null, "Google")).toBe("Own Name");
    expect(identityName(parseProfile("u1", {}), null, "Google")).toBe("Google");
    expect(identityName(parseProfile("u1", {}), null, null)).toBe("");
  });
});

describe("readProfile", () => {
  const data = { roles: ["scouter"] };
  it("reads an existing document from cache or server", () => {
    expect(
      readProfile("u1", { exists: true, fromCache: true, data }).kind,
    ).toBe("profile");
    expect(
      readProfile("u1", { exists: true, fromCache: false, data }).kind,
    ).toBe("profile");
  });

  it("calls a missing document missing only when the server said so", () => {
    expect(
      readProfile("u1", { exists: false, fromCache: false, data: undefined })
        .kind,
    ).toBe("missing");
    expect(
      readProfile("u1", { exists: false, fromCache: true, data: undefined })
        .kind,
    ).toBe("unknown");
  });
});

const base: RolesInput = {
  auth: "signed-in",
  uid: "u1",
  authName: "Google Name",
  read: null,
  canonicalName: null,
  stalled: false,
  online: true,
};

describe("rolesState", () => {
  it("is loading, never no access, while auth or the profile is pending", () => {
    expect(rolesState({ ...base, auth: "loading", uid: null }).status).toBe(
      "loading",
    );
    expect(rolesState({ ...base, auth: "signing-in", uid: null }).status).toBe(
      "loading",
    );
    expect(rolesState(base).status).toBe("loading");
    expect(rolesState({ ...base, read: { kind: "unknown" } }).status).toBe(
      "loading",
    );
  });

  it("is signed out only when auth says so", () => {
    expect(rolesState({ ...base, auth: "signed-out", uid: null }).status).toBe(
      "signed-out",
    );
  });

  it("is unavailable when the profile cannot be read, not no access", () => {
    expect(rolesState({ ...base, read: { kind: "error" } }).status).toBe(
      "unavailable",
    );
    expect(rolesState({ ...base, stalled: true }).status).toBe("unavailable");
    expect(
      rolesState({ ...base, read: { kind: "unknown" }, online: false }).status,
    ).toBe("unavailable");
    expect(
      rolesState({ ...base, read: { kind: "unknown" }, stalled: true }).status,
    ).toBe("unavailable");
  });

  it("gives a server-confirmed missing profile the scouter role", () => {
    expect(rolesState({ ...base, read: { kind: "missing" } })).toEqual({
      status: "ready",
      uid: "u1",
      roles: ["scouter"],
      displayName: "Google Name",
      identityUids: ["u1"],
    });
  });

  it("returns the roles, name and uids of a profile", () => {
    const profile = parseProfile("u1", {
      roles: ["scouter"],
      displayName: "Own Name",
      canonicalUid: "p1",
    });
    expect(
      rolesState({
        ...base,
        read: { kind: "profile", profile },
        canonicalName: "Primary Name",
      }),
    ).toEqual({
      status: "ready",
      uid: "u1",
      roles: ["scouter"],
      displayName: "Primary Name",
      identityUids: ["u1", "p1"],
    });
  });
});

describe("newProfileDoc", () => {
  it("matches the shape the rules allow for a first sign-in", () => {
    expect(
      newProfileDoc(
        "u1",
        "Scout A",
        "a@example.com",
        new Date(Date.UTC(2026, 0, 2)),
      ),
    ).toEqual({
      uid: "u1",
      displayName: "Scout A",
      email: "a@example.com",
      roles: ["scouter"],
      createdAt: "2026-01-02T00:00:00.000Z",
    });
    expect(newProfileDoc("u1", "", null, new Date(0))).not.toHaveProperty(
      "email",
    );
  });
});

describe("canDeleteEntry", () => {
  it("lets a writer delete their own entry and a lead delete any", () => {
    expect(canDeleteEntry(["scouter"], "u1", "u1")).toBe(true);
    expect(canDeleteEntry(["scouter"], "u1", "u2")).toBe(false);
    for (const role of ["strategy", "admin", "developer"] as const) {
      expect(canDeleteEntry([role], "u1", "u2")).toBe(true);
    }
  });

  it("denies a mentor, a viewer and a signed-out account", () => {
    expect(canDeleteEntry(["mentor"], "u1", "u1")).toBe(false);
    expect(canDeleteEntry(["viewer"], "u1", "u1")).toBe(false);
    expect(canDeleteEntry(["scouter"], null, "")).toBe(false);
  });
});
