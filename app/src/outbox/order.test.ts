import { describe, expect, it } from "vitest";
import { sendOrder, supersede } from "./order";

describe("supersede", () => {
  it("drops older unconfirmed writes to the same path only", () => {
    const items = [
      { id: "a", path: "pit/1", status: "on-device" as const },
      { id: "b", path: "pit/1", status: "sending" as const },
      { id: "c", path: "pit/1", status: "in-database" as const },
      { id: "d", path: "pit/1", status: "refused" as const },
      { id: "e", path: "pit/2", status: "on-device" as const },
    ];
    const { kept, dropped } = supersede(items, "pit/1");
    expect(dropped.map((i) => i.id)).toEqual(["a", "b"]);
    expect(kept.map((i) => i.id)).toEqual(["c", "d", "e"]);
  });
});

describe("supersede with merge writes", () => {
  const items = [
    {
      id: "m2",
      path: "pit/1",
      status: "on-device" as const,
      kind: "merge" as const,
    },
    {
      id: "s1",
      path: "pit/1",
      status: "sending" as const,
      kind: "set" as const,
    },
    { id: "old", path: "pit/1", status: "on-device" as const },
    {
      id: "m0",
      path: "pit/1",
      status: "in-database" as const,
      kind: "merge" as const,
    },
    {
      id: "other",
      path: "pit/2",
      status: "on-device" as const,
      kind: "merge" as const,
    },
  ];

  it("a newer set drops older unconfirmed sets and merges for the path", () => {
    const { kept, dropped } = supersede(items, "pit/1", "set");
    expect(dropped.map((i) => i.id)).toEqual(["m2", "s1", "old"]);
    expect(kept.map((i) => i.id)).toEqual(["m0", "other"]);
  });

  it("a merge drops nothing, and is never dropped by another merge", () => {
    const { kept, dropped } = supersede(items, "pit/1", "merge");
    expect(dropped).toEqual([]);
    expect(kept.map((i) => i.id)).toEqual(["m2", "s1", "old", "m0", "other"]);
  });

  it("treats an item with no kind as a set", () => {
    const { dropped } = supersede(
      [{ id: "a", path: "pit/1", status: "on-device" as const }],
      "pit/1",
    );
    expect(dropped.map((i) => i.id)).toEqual(["a"]);
  });
});

describe("supersede with delete writes", () => {
  const items = [
    {
      id: "m",
      path: "pit/1",
      status: "on-device" as const,
      kind: "merge" as const,
    },
    {
      id: "d",
      path: "pit/1",
      status: "sending" as const,
      kind: "delete" as const,
    },
    {
      id: "done",
      path: "pit/1",
      status: "in-database" as const,
      kind: "set" as const,
    },
    {
      id: "other",
      path: "pit/2",
      status: "on-device" as const,
      kind: "delete" as const,
    },
  ];

  it("a newer delete drops older unconfirmed writes for the path", () => {
    const { kept, dropped } = supersede(items, "pit/1", "delete");
    expect(dropped.map((i) => i.id)).toEqual(["m", "d"]);
    expect(kept.map((i) => i.id)).toEqual(["done", "other"]);
  });

  it("a newer set drops an unconfirmed delete for the path", () => {
    const { dropped } = supersede(items, "pit/1", "set");
    expect(dropped.map((i) => i.id)).toEqual(["m", "d"]);
  });

  it("a merge keeps an unconfirmed delete", () => {
    const { kept, dropped } = supersede(items, "pit/1", "merge");
    expect(dropped).toEqual([]);
    expect(kept).toHaveLength(4);
  });
});

describe("sendOrder", () => {
  it("sends the oldest item first", () => {
    const items = ["new", "mid", "old"];
    expect(sendOrder(items)).toEqual(["old", "mid", "new"]);
    expect(items).toEqual(["new", "mid", "old"]);
  });

  it("sends a merge after the set it was made after, even when both are kept", () => {
    const stored = [{ id: "merge" }, { id: "set" }];
    expect(sendOrder(stored).map((i) => i.id)).toEqual(["set", "merge"]);
  });

  it("sends a delete after the set it was made after", () => {
    const stored = [{ id: "delete" }, { id: "set" }];
    expect(sendOrder(stored).map((i) => i.id)).toEqual(["set", "delete"]);
  });
});
