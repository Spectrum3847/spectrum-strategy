import { describe, expect, it, vi } from "vitest";
import { matchLabel, matchOrder, parseMatchKey } from "./matchKey";
import {
  parseEventEntry,
  parsePitEntry,
  parsePrescoutEntry,
  parseTrexReport,
} from "./parse";
import { createStore, feedStore, idleFeed } from "./store";
import {
  fetchEventSnapshot,
  parseEventMatches,
  parseRankings,
  parseTeams,
} from "./tbaEvent";

describe("match keys", () => {
  it("reads qualification and playoff keys", () => {
    expect(parseMatchKey("2027test_qm12")).toEqual({
      level: "qm",
      set: 1,
      number: 12,
    });
    expect(parseMatchKey("2027test_sf3m2")).toEqual({
      level: "sf",
      set: 3,
      number: 2,
    });
    expect(parseMatchKey("2027test_f1m1")).toEqual({
      level: "f",
      set: 1,
      number: 1,
    });
    expect(parseMatchKey("typed:2027test:5")).toBeNull();
  });

  it("labels and orders matches", () => {
    expect(matchLabel("2027test_qm12")).toBe("Q12");
    expect(matchLabel("2027test_sf3m1")).toBe("SF3");
    expect(matchLabel("2027test_sf3m2")).toBe("SF3 M2");
    expect(matchLabel("2027test_f1m2")).toBe("F2");
    expect(matchLabel("odd")).toBe("odd");
    const keys = [
      "2027test_f1m1",
      "2027test_qm10",
      "2027test_qm2",
      "2027test_sf1m1",
    ];
    expect([...keys].sort((a, b) => matchOrder(a) - matchOrder(b))).toEqual([
      "2027test_qm2",
      "2027test_qm10",
      "2027test_sf1m1",
      "2027test_f1m1",
    ]);
  });
});

describe("document parsing", () => {
  it("reads a scout entry and credits the station scout first", () => {
    const entry = parseEventEntry("e1", {
      teamNumber: 1111,
      alliance: "Red",
      tbaMatchKey: "2027test_qm1",
      authorDisplayName: "Account A",
      scoutedByName: "Scout A",
      updatedAt: "2027-03-01T10:00:00.000Z",
      fieldValues: { autoFuelScored: 3 },
    });
    expect(entry).toEqual({
      id: "e1",
      teamNumber: 1111,
      alliance: "Red",
      tbaMatchKey: "2027test_qm1",
      scoutName: "Scout A",
      scoutedByName: "Scout A",
      authorDisplayName: "Account A",
      scouterUid: "",
      authorUid: "",
      updatedAt: "2027-03-01T10:00:00.000Z",
      fieldValues: { autoFuelScored: 3 },
    });
  });

  it("keeps who an entry counts for and whether a lead keyed it in", () => {
    const credited = parseEventEntry("e3", {
      authorUid: "u1",
      scoutedByName: "Scout A",
      scoutedByUid: "u2",
      addedManually: true,
    });
    expect(credited).toMatchObject({ scouterUid: "u2", addedManually: true });
    const own = parseEventEntry("e4", { authorUid: "u1" });
    expect(own.scouterUid).toBe("u1");
    expect(own.addedManually).toBeUndefined();
  });

  it("treats wrong types as missing", () => {
    const entry = parseEventEntry("e2", {
      teamNumber: "2222",
      fieldValues: "nope",
      tbaMatchKey: 7,
    });
    expect(entry).toMatchObject({
      teamNumber: 2222,
      fieldValues: {},
      tbaMatchKey: null,
      scoutName: "",
    });
  });

  it("reads pit, prescout and T-REx records", () => {
    expect(
      parsePitEntry("p", {
        teamNumber: 1111,
        photoKeys: ["a", 2, "b"],
        eventKey: "2027test",
        authorUid: "u1",
      }),
    ).toMatchObject({
      teamNumber: 1111,
      photoKeys: ["a", "b"],
      eventKey: "2027test",
      authorUid: "u1",
    });
    expect(
      parsePrescoutEntry("q", {
        teamNumber: 2222,
        fieldValues: { matchNumber: "4" },
      }),
    ).toMatchObject({ teamNumber: 2222, fieldValues: { matchNumber: "4" } });
    expect(
      parseTrexReport("t", {
        trait: "defense",
        teamNumber: 1111,
        matchNumber: 5,
        report: "Pins often",
        authorDisplayName: "Scout B",
      }),
    ).toMatchObject({
      trait: "defense",
      matchNumber: 5,
      scoutName: "Scout B",
      rating: null,
    });
    const rating = (value: unknown) =>
      parseTrexReport("t", { trait: "defense", rating: value }).rating;
    expect(rating(4)).toBe(4);
    for (const bad of [0, 6, 2.5, "3", null]) expect(rating(bad)).toBeNull();
  });
});

describe("report drawings", () => {
  it("keeps an entry's strokesByPhase and a trait report's strokes", () => {
    const strokes = { auton: [{ points: [] }] };
    expect(
      parseEventEntry("e", { strokesByPhase: strokes }).strokesByPhase,
    ).toEqual(strokes);
    expect(parseEventEntry("e", {})).not.toHaveProperty("strokesByPhase");
    expect(parseEventEntry("e", { strokesByPhase: {} })).not.toHaveProperty(
      "strokesByPhase",
    );
    expect(parseTrexReport("r", { strokes: [{ points: [] }] }).strokes).toEqual(
      [{ points: [] }],
    );
    expect(parseTrexReport("r", { strokes: "x" })).not.toHaveProperty(
      "strokes",
    );
  });
});

describe("TBA parsing", () => {
  it("reads teams with nicknames", () => {
    expect(
      parseTeams([
        { team_number: 2222, nickname: " Beta " },
        { team_number: 1111, nickname: "Alpha" },
        { nickname: "No number" },
      ]),
    ).toEqual([
      { number: 1111, nickname: "Alpha" },
      { number: 2222, nickname: "Beta" },
    ]);
    expect(parseTeams(null)).toEqual([]);
  });

  it("reads rankings with the record, and none before quals", () => {
    expect(
      parseRankings({
        rankings: [
          {
            rank: 2,
            team_key: "frc2222",
            record: { wins: 3, losses: 4, ties: 0 },
          },
          {
            rank: 1,
            team_key: "frc1111",
            record: { wins: 6, losses: 1, ties: 1 },
          },
        ],
      }),
    ).toEqual([
      { team: 1111, rank: 1, wins: 6, losses: 1, ties: 1 },
      { team: 2222, rank: 2, wins: 3, losses: 4, ties: 0 },
    ]);
    expect(parseRankings(null)).toEqual([]);
  });

  it("reads results, with no score for an unplayed match", () => {
    const matches = parseEventMatches([
      {
        key: "2027test_qm2",
        alliances: {
          red: { team_keys: ["frc1111"], score: -1 },
          blue: { team_keys: ["frc2222"], score: -1 },
        },
        winning_alliance: "",
      },
      {
        key: "2027test_qm1",
        alliances: {
          red: { team_keys: ["frc1111", "frc3333"], score: 40 },
          blue: { team_keys: ["frc2222"], score: 35 },
        },
        winning_alliance: "red",
      },
    ]);
    expect(matches.map((m) => m.key)).toEqual(["2027test_qm1", "2027test_qm2"]);
    expect(matches[0]).toMatchObject({
      red: [1111, 3333],
      redScore: 40,
      blueScore: 35,
      winner: "red",
    });
    expect(matches[1]).toMatchObject({ redScore: null, winner: null });
  });

  it("keeps the last copy of a part that fails to load", async () => {
    const previous = {
      fetchedAt: "then",
      teams: [{ number: 1111, nickname: "Alpha" }],
      rankings: [],
      matches: [],
    };
    const fetcher = vi.fn((url: string) =>
      url.endsWith("/teams/simple")
        ? Promise.resolve(new Response("no", { status: 500 }))
        : Promise.resolve(
            Response.json(url.endsWith("/rankings") ? { rankings: null } : []),
          ),
    ) as unknown as typeof fetch;
    const snapshot = await fetchEventSnapshot(
      "2027test",
      "key",
      previous,
      fetcher,
    );
    expect(snapshot.teams).toEqual(previous.teams);
    expect(snapshot.fetchedAt).not.toBe("then");
  });

  it("fails when every part fails", async () => {
    const fetcher = (() =>
      Promise.resolve(
        new Response("no", { status: 401 }),
      )) as unknown as typeof fetch;
    await expect(
      fetchEventSnapshot("2027test", "bad", null, fetcher),
    ).rejects.toThrow("TBA answered 401");
  });
});

describe("shared stores", () => {
  it("starts on the first subscriber and stops on the last", () => {
    const stop = vi.fn();
    const start = vi.fn(() => stop);
    const store = createStore(0, start);
    const a = store.subscribe(() => undefined);
    const b = store.subscribe(() => undefined);
    expect(start).toHaveBeenCalledTimes(1);
    a();
    expect(stop).not.toHaveBeenCalled();
    b();
    expect(stop).toHaveBeenCalledTimes(1);
  });

  it("reports ready on the first snapshot and failed on an error", () => {
    let push: (items: number[]) => void = () => undefined;
    let fail: () => void = () => undefined;
    const store = feedStore<number>((onItems, onError) => {
      push = onItems;
      fail = onError;
      return () => undefined;
    });
    store.subscribe(() => undefined);
    expect(store.get()).toBe(idleFeed);
    push([1, 2]);
    expect(store.get()).toEqual({ items: [1, 2], ready: true, failed: false });
    fail();
    expect(store.get()).toEqual({ items: [1, 2], ready: true, failed: true });
  });
});
