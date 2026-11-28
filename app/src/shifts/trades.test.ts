import { describe, expect, it } from "vitest";
import {
  acceptedTrades,
  parseShifts,
  parseTradeDocs,
  parseTrades,
} from "../scout/credit";
import {
  answeredTrade,
  newTrade,
  pendingFor,
  tradedWith,
  tradeTargets,
} from "./trades";

const now = new Date("2027-03-04T05:06:07.123Z");

const allowed = [
  "id",
  "eventKey",
  "requesterUid",
  "requesterDisplayName",
  "targetUid",
  "targetDisplayName",
  "requesterBlock",
  "targetBlock",
  "status",
  "createdAt",
  "updatedAt",
  "updatedAtTs",
];

const stored = (over: Record<string, unknown> = {}) => ({
  id: "t1",
  eventKey: "2027test",
  requesterUid: "u1",
  requesterDisplayName: "Scout A ",
  targetUid: "u2",
  targetDisplayName: "Scout B",
  requesterBlock: { startMatch: 7, endMatch: 12 },
  status: "pending",
  createdAt: "2027-03-04T01:00:00.000Z",
  updatedAt: "2027-03-04T01:00:00.000Z",
  ...over,
});

describe("newTrade", () => {
  const block = { startMatch: 7, endMatch: 12, station: "R2" };
  const doc = newTrade({
    id: "t1",
    eventKey: "2027test",
    requester: { uid: "u1", displayName: "Scout A" },
    target: { uid: "u2", name: "Scout B" },
    block,
    now,
  });

  it("writes a pending request with only keys the rules allow", () => {
    expect(Object.keys(doc).every((k) => allowed.includes(k))).toBe(true);
    expect(doc.status).toBe("pending");
    expect(doc.id).toBe("t1");
    expect(doc).not.toHaveProperty("targetBlock");
    expect(doc.createdAt).toBe(doc.updatedAt);
  });

  it("keeps exactly startMatch and endMatch in the block", () => {
    expect(doc.requesterBlock).toEqual({ startMatch: 7, endMatch: 12 });
  });

  it("caps display names at the rules' 128 characters", () => {
    const long = newTrade({
      id: "t2",
      eventKey: "e",
      requester: { uid: "u1", displayName: "x".repeat(200) },
      target: { uid: "u2", name: "y".repeat(200) },
      block: { startMatch: 1, endMatch: 2 },
      now,
    });
    expect(String(long.requesterDisplayName)).toHaveLength(128);
    expect(String(long.targetDisplayName)).toHaveLength(128);
  });
});

describe("answeredTrade", () => {
  it("changes only status and the update stamps", () => {
    const [trade] = parseTradeDocs([stored()]);
    if (!trade) throw new Error("no trade");
    const next = answeredTrade(trade, "accepted", now);
    const changed = Object.keys(next).filter(
      (k) =>
        JSON.stringify(next[k]) !== JSON.stringify(trade.source[k]) &&
        !(k === "updatedAtTs" && !(k in trade.source)),
    );
    expect(changed.sort()).toEqual(["status", "updatedAt"]);
    expect(Object.keys(next).sort()).toEqual(
      [...Object.keys(trade.source), "updatedAtTs"].sort(),
    );
    expect(next.status).toBe("accepted");
    expect(next.updatedAt).toBe("2027-03-04T05:06:07.123Z");
    expect(next.requesterDisplayName).toBe("Scout A ");
  });
});

describe("parseTradeDocs", () => {
  it("reads every status, newest first, strings as stored", () => {
    const trades = parseTradeDocs([
      stored({ id: "a", status: "declined" }),
      stored({
        id: "b",
        status: "cancelled",
        createdAt: "2027-03-04T03:00:00.000Z",
      }),
      stored({
        id: "c",
        status: "accepted",
        targetBlock: { startMatch: 1, endMatch: 6 },
      }),
      stored({ id: "d", status: "weird" }),
    ]);
    expect(trades.map((t) => t.id)).toEqual(["b", "a", "c", "d"]);
    expect(trades.map((t) => t.status)).toEqual([
      "cancelled",
      "declined",
      "accepted",
      "pending",
    ]);
    expect(trades[1]?.requesterDisplayName).toBe("Scout A ");
    expect(trades[2]?.targetBlock).toEqual({ startMatch: 1, endMatch: 6 });
  });

  it("skips junk and trades with no valid block", () => {
    expect(
      parseTradeDocs([
        null,
        3,
        stored({ requesterBlock: { startMatch: 0, endMatch: 1 } }),
      ]),
    ).toEqual([]);
  });

  it("keeps parseTrades to the accepted ones", () => {
    const docs = [stored({ status: "accepted" }), stored({ id: "p" })];
    expect(parseTrades(docs)).toHaveLength(1);
    expect(acceptedTrades(parseTradeDocs(docs))).toEqual(parseTrades(docs));
  });
});

describe("trade helpers", () => {
  const trades = parseTradeDocs([
    stored({ id: "p1" }),
    stored({ id: "p2", requesterUid: "u3", targetUid: "u4" }),
    stored({
      id: "x",
      status: "accepted",
      targetBlock: { startMatch: 1, endMatch: 6 },
    }),
    stored({ id: "", status: "pending" }),
  ]);

  it("lists pending trades on either side, with an id", () => {
    expect(pendingFor(trades, "u1").map((t) => t.id)).toEqual(["p1"]);
    expect(pendingFor(trades, "u2").map((t) => t.id)).toEqual(["p1"]);
    expect(pendingFor(trades, null)).toEqual([]);
  });

  it("names who a block came from", () => {
    expect(tradedWith(trades, "u2")).toEqual([
      { block: { startMatch: 7, endMatch: 12 }, name: "Scout A " },
    ]);
    expect(tradedWith(trades, "u1")).toEqual([
      { block: { startMatch: 1, endMatch: 6 }, name: "Scout B" },
    ]);
  });

  it("offers linked teammates, not yourself, once each", () => {
    const shifts = parseShifts({
      roster: [
        { uid: "u1", name: "Scout A" },
        { uid: "u2", name: "Scout B" },
        { uid: "", name: "Scout C" },
        { uid: "u2", name: "Scout B again" },
      ],
    });
    if (!shifts) throw new Error("no grid");
    expect(tradeTargets(shifts, "u1").map((r) => r.name)).toEqual(["Scout B"]);
  });
});
