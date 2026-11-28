import { describe, expect, it } from "vitest";
import {
  byDisplayName,
  matchesSearch,
  normalizeRoles,
  parseManaged,
  rolesText,
  usersView,
} from "./profiles";

describe("parseManaged", () => {
  it("reads a stored profile and keeps the raw document", () => {
    const data = {
      uid: "u1",
      displayName: "Scout A",
      email: "a@example.test",
      roles: ["scouter", "wizard"],
      canonicalUid: "p1",
      linkedEmails: ["b@example.test", 7],
      createdAt: "2027-01-01T00:00:00.000Z",
    };
    const p = parseManaged("u1", data);
    expect(p).toMatchObject({
      displayName: "Scout A",
      email: "a@example.test",
      roles: ["scouter"],
      canonicalUid: "p1",
      linkedEmails: ["b@example.test"],
    });
    expect(p.raw).toBe(data);
  });

  it("falls back to no email, viewer and no name", () => {
    const p = parseManaged("u2", {});
    expect(p).toMatchObject({
      displayName: "",
      email: null,
      roles: ["viewer"],
      canonicalUid: null,
      linkedEmails: [],
    });
  });
});

describe("list helpers", () => {
  it("orders by name without case, then uid", () => {
    const list = [
      parseManaged("2", { displayName: "scout b" }),
      parseManaged("1", { displayName: "Scout B" }),
      parseManaged("3", { displayName: "Scout A" }),
      parseManaged("4", {}),
    ].sort(byDisplayName);
    expect(list.map((p) => p.uid)).toEqual(["4", "3", "1", "2"]);
  });

  it("searches name and email, ignoring case and spaces around", () => {
    const p = parseManaged("u1", {
      displayName: "Scout A",
      email: "Lead@Example.test",
    });
    expect(matchesSearch(p, "")).toBe(true);
    expect(matchesSearch(p, " scout ")).toBe(true);
    expect(matchesSearch(p, "lead@example")).toBe(true);
    expect(matchesSearch(p, "u1")).toBe(false);
    expect(matchesSearch(p, "nobody")).toBe(false);
  });

  it("names roles alphabetically and never saves an empty set", () => {
    expect(rolesText(["strategy", "admin"])).toBe("Admin, Strategist");
    expect(rolesText(["mentor", "scouter"])).toBe("Mentor, Scouter");
    expect(normalizeRoles(["mentor", "scouter"])).toEqual([
      "scouter",
      "mentor",
    ]);
    expect(normalizeRoles([])).toEqual(["viewer"]);
    expect(normalizeRoles(["developer", "viewer"])).toEqual([
      "viewer",
      "developer",
    ]);
  });
});

describe("usersView", () => {
  const seen = {
    ready: true,
    failed: false,
    code: null,
    fromCache: false,
    count: 3,
  };

  it("waits for the first snapshot", () => {
    expect(usersView({ ...seen, ready: false })).toEqual({ kind: "loading" });
  });

  it("tells a refused read from a failed one", () => {
    const failed = { ...seen, failed: true };
    expect(usersView({ ...failed, code: "permission-denied" })).toEqual({
      kind: "refused",
    });
    expect(
      usersView({ ...failed, code: "firestore/permission-denied" }),
    ).toEqual({ kind: "refused" });
    expect(usersView({ ...failed, code: "unavailable" })).toEqual({
      kind: "failed",
    });
  });

  it("does not call an empty cache an empty list", () => {
    expect(usersView({ ...seen, count: 0, fromCache: true })).toEqual({
      kind: "nothing-cached",
    });
    expect(usersView({ ...seen, count: 0 })).toEqual({ kind: "empty" });
  });

  it("says where a list came from", () => {
    expect(usersView(seen)).toEqual({ kind: "list", source: "server" });
    expect(usersView({ ...seen, fromCache: true })).toEqual({
      kind: "list",
      source: "cache",
    });
  });
});
