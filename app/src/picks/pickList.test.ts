import { Timestamp } from "firebase/firestore";
import { describe, expect, it } from "vitest";
import {
  addTier,
  applyLayout,
  applyName,
  defaultTierNames,
  type Layout,
  layoutOf,
  markDnp,
  maxTeams,
  moveBy,
  newList,
  type PickList,
  parsePickList,
  pickListDoc,
  placeTeam,
  refusalNote,
  removeTeam,
  removeTier,
  renameTier,
  setReason,
} from "./pickList";

const list = (over: Partial<PickList> = {}): PickList => ({
  id: "list-1",
  name: "Quals",
  teamNumbers: [],
  tiers: [],
  dnp: [],
  authorUid: "u1",
  authorDisplayName: "Lead A",
  updatedMs: 1_000,
  ...over,
});

const layout = (tiers: number[][], dnp: Layout["dnp"] = []): Layout => ({
  tiers: tiers.map((teams, i) => ({ name: `T${i}`, teams })),
  dnp,
});
const teamsOf = (l: Layout) => l.tiers.map((t) => t.teams);

describe("parsePickList", () => {
  it("reads a stored document", () => {
    const parsed = parsePickList("list-1", {
      id: "list-1",
      name: "Quals",
      teamNumbers: [1111, 2222],
      tiers: [{ name: "1st pick", teams: [1111, 2222] }],
      dnp: [{ team: 3333, reason: "Died" }],
      authorUid: "u1",
      authorDisplayName: "Lead A",
      updatedAt: "2027-03-01T10:00:00.000Z",
      updatedAtTs: Timestamp.fromMillis(5_000),
    });
    expect(parsed).toMatchObject({
      teamNumbers: [1111, 2222],
      tiers: [{ name: "1st pick", teams: [1111, 2222] }],
      dnp: [{ team: 3333, reason: "Died" }],
      updatedMs: 5_000,
    });
  });

  it("drops junk instead of hiding the list", () => {
    const parsed = parsePickList("x", {
      teamNumbers: [1111, "bad", 0, 123456, null],
      tiers: ["nope", { name: "A", teams: [2222, "x"] }],
      dnp: [{ team: "x" }, { team: 4444 }],
      updatedAt: "2027-03-01T10:00:00.000Z",
    });
    expect(parsed.teamNumbers).toEqual([1111]);
    expect(parsed.tiers).toEqual([{ name: "A", teams: [2222] }]);
    expect(parsed.dnp).toEqual([{ team: 4444, reason: "" }]);
    expect(parsed.updatedMs).toBe(Date.parse("2027-03-01T10:00:00.000Z"));
  });
});

describe("layoutOf", () => {
  it("starts a list with no tiers on the default names", () => {
    const l = layoutOf(list());
    expect(l.tiers.map((t) => t.name)).toEqual(defaultTierNames);
  });

  it("lets teamNumbers win when another writer changed only it", () => {
    const l = layoutOf(
      list({
        teamNumbers: [2222, 5555],
        tiers: [
          { name: "A", teams: [1111, 2222] },
          { name: "B", teams: [3333] },
        ],
        dnp: [
          { team: 5555, reason: "x" },
          { team: 6666, reason: "y" },
        ],
      }),
    );
    expect(teamsOf(l)).toEqual([[2222, 5555], []]);
    expect(l.dnp).toEqual([{ team: 6666, reason: "y" }]);
  });

  it("keeps a team in one place", () => {
    const l = layoutOf(
      list({
        teamNumbers: [1111],
        tiers: [
          { name: "A", teams: [1111] },
          { name: "B", teams: [1111] },
        ],
      }),
    );
    expect(teamsOf(l)).toEqual([[1111], []]);
  });
});

describe("moving teams", () => {
  it("steps within a tier and across a tier heading", () => {
    const l = layout([[1, 2], [3]]);
    expect(teamsOf(moveBy(l, 2, 1))).toEqual([[1], [2, 3]]);
    expect(teamsOf(moveBy(l, 3, -1))).toEqual([[1, 2, 3], []]);
    expect(teamsOf(moveBy(l, 2, -1))).toEqual([[2, 1], [3]]);
  });

  it("stops at the ends", () => {
    const l = layout([[1, 2], [3]]);
    expect(moveBy(l, 1, -1)).toEqual(l);
    expect(moveBy(l, 3, 1)).toEqual(l);
  });

  it("reaches an empty tier", () => {
    expect(teamsOf(moveBy(layout([[1], [], [2]]), 1, 1))).toEqual([
      [],
      [1],
      [2],
    ]);
  });

  it("places a team at a spot in a tier and takes it from its old place", () => {
    const l = layout([[1, 2], [3]], [{ team: 9, reason: "x" }]);
    expect(teamsOf(placeTeam(l, 1, 1, 1))).toEqual([[2], [3, 1]]);
    expect(teamsOf(placeTeam(l, 3, 0, 0))).toEqual([[3, 1, 2], []]);
    const fromDnp = placeTeam(l, 9, 0);
    expect(teamsOf(fromDnp)).toEqual([[1, 2, 9], [3]]);
    expect(fromDnp.dnp).toEqual([]);
  });

  it("refuses a new team on a full list", () => {
    const full = layout([Array.from({ length: maxTeams }, (_, i) => i + 1)]);
    expect(placeTeam(full, 99, 0)).toBe(full);
    expect(placeTeam(full, 1, 0, 5)).not.toBe(full);
  });
});

describe("do not pick", () => {
  it("moves a team off the tiers with its reason", () => {
    const l = markDnp(layout([[1, 2]]), 2, "  Died in Q4  ");
    expect(teamsOf(l)).toEqual([[1]]);
    expect(l.dnp).toEqual([{ team: 2, reason: "Died in Q4" }]);
    expect(setReason(l, 2, "Red card").dnp[0]?.reason).toBe("Red card");
    expect(removeTeam(l, 2).dnp).toEqual([]);
  });
});

describe("tiers", () => {
  it("renames, adds and removes empty tiers only", () => {
    const l = layout([[1], []]);
    expect(renameTier(l, 0, " Top ").tiers[0]?.name).toBe("Top");
    expect(renameTier(l, 0, "  ")).toBe(l);
    expect(addTier(l, "Late").tiers).toHaveLength(3);
    expect(removeTier(l, 0)).toBe(l);
    expect(removeTier(l, 1).tiers).toHaveLength(1);
    expect(removeTier(layout([[]]), 0).tiers).toHaveLength(1);
  });
});

describe("saving", () => {
  it("writes teamNumbers as the tiers flattened and keeps the author", () => {
    const next = applyLayout(
      list({ authorUid: "creator" }),
      layout([[1, 2], [3]], [{ team: 9, reason: "x" }]),
      5_000,
    );
    expect(next.teamNumbers).toEqual([1, 2, 3]);
    expect(next.authorUid).toBe("creator");
    expect(next.updatedMs).toBe(5_000);
  });

  it("never stamps behind the stored revision", () => {
    expect(
      applyLayout(list({ updatedMs: 9_000 }), layout([[]]), 5_000).updatedMs,
    ).toBe(9_000);
    expect(applyName(list({ updatedMs: 9_000 }), "New", 5_000).updatedMs).toBe(
      9_000,
    );
  });

  it("keeps the old name for an empty one", () => {
    expect(applyName(list(), "  ", 2_000).name).toBe("Quals");
  });

  it("writes the document shape the rules accept", () => {
    const doc = pickListDoc(
      applyLayout(
        list(),
        layout([[1, 2]], [{ team: 9, reason: "Died" }]),
        5_000,
      ),
    );
    expect(Object.keys(doc).sort()).toEqual(
      [
        "authorDisplayName",
        "authorUid",
        "dnp",
        "id",
        "name",
        "teamNumbers",
        "tiers",
        "updatedAt",
        "updatedAtTs",
      ].sort(),
    );
    expect(doc.teamNumbers).toEqual([1, 2]);
    expect(doc.tiers).toEqual([{ name: "T0", teams: [1, 2] }]);
    expect(doc.dnp).toEqual([{ team: 9, reason: "Died" }]);
    expect(doc.updatedAt).toBe(new Date(5_000).toISOString());
    expect((doc.updatedAtTs as Timestamp).toMillis()).toBe(5_000);
  });

  it("leaves tiers and dnp out while empty", () => {
    const doc = pickListDoc(list());
    expect("tiers" in doc).toBe(false);
    expect("dnp" in doc).toBe(false);
  });

  it("makes a new list", () => {
    const made = newList("  ", { uid: "u1", displayName: "Lead A" }, 7_000);
    expect(made).toMatchObject({
      name: "Untitled list",
      teamNumbers: [],
      tiers: [],
      authorUid: "u1",
    });
    expect(made.id).not.toBe("");
  });
});

describe("refusalNote", () => {
  it("says another lead was first when the list moved past our stamp", () => {
    expect(refusalNote(1_000, 2_000)).toMatch(/newer version/);
  });

  it("does not guess otherwise", () => {
    expect(refusalNote(2_000, 1_000)).toMatch(/refused/);
    expect(refusalNote(null, 1_000)).not.toMatch(/newer version/);
  });
});
