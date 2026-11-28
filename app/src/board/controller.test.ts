import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BoardController, type Context, type Deps } from "./controller";
import type { LocalRecord } from "./local";
import { newSession, type Session, sessionJson } from "./model";

const t0 = 1_800_000_000_000;
const robots = [
  ...[1111, 2222, 3333].map((team) => ({ team, side: "red" as const })),
  ...[4444, 5555, 6666].map((team) => ({ team, side: "blue" as const })),
];
const ctx: Context = {
  eventKey: "2027test",
  matchNumber: 3,
  alliance: "Red",
  robots,
  fieldId: "2026-rebuilt",
};
const lead = { uid: "u1", displayName: "Lead A" };
const dot = [
  { x: 0.1, y: 0.1 },
  { x: 0.2, y: 0.2 },
];

function session(id: string, updatedMs: number, uid = "u1"): Session {
  return newSession({
    id,
    eventKey: "2027test",
    matchNumber: 3,
    alliance: "Red",
    teamNumbers: robots.map((r) => r.team),
    fieldId: "2026-rebuilt",
    author: { uid, displayName: uid === "" ? "" : "Lead A" },
    nowMs: updatedMs,
  });
}

const recordOf = (s: Session, queuedMs: number): LocalRecord => ({
  doc: sessionJson(s),
  queuedMs,
});

function setup(options: { record?: LocalRecord; saveFails?: boolean } = {}) {
  const log = {
    saved: [] as LocalRecord[],
    sent: [] as Record<string, unknown>[],
    unsent: new Set<string>(),
    now: t0,
    active: 0,
    most: 0,
  };
  const discard = vi.fn();
  const deps: Deps = {
    load: async () => options.record ?? null,
    save: async (record) => {
      log.active++;
      log.most = Math.max(log.most, log.active);
      await Promise.resolve();
      log.active--;
      if (options.saveFails) throw new Error("full");
      log.saved.push(record);
    },
    enqueue: async (doc) => {
      log.sent.push(doc);
    },
    unsent: (id) => log.unsent.has(id),
    discard,
    now: () => log.now,
    newId: () => "board-1",
    debounceMs: 1000,
  };
  const c = new BoardController(deps, ctx);
  c.setAuthor(lead);
  return { c, log, discard };
}

async function open(
  s: ReturnType<typeof setup>,
  remote: Session | null = null,
  fromCache = false,
) {
  s.c.setRemote(remote, true, fromCache);
  await s.c.start();
}

const settle = () => vi.advanceTimersByTimeAsync(0);
const wait = (ms: number) => vi.advanceTimersByTimeAsync(ms);

beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

describe("a blank board", () => {
  it("writes nothing until something is drawn", async () => {
    const s = setup();
    await open(s);
    await wait(5000);
    const state = s.c.getSnapshot();
    expect(state.ready).toBe(true);
    expect(state.hasBoard).toBe(false);
    expect(s.log.saved).toHaveLength(0);
    expect(s.log.sent).toHaveLength(0);
  });

  it("waits for the database's first answer, then for the wait to end", async () => {
    const s = setup();
    await s.c.start();
    expect(s.c.getSnapshot().ready).toBe(false);
    s.c.proceed();
    expect(s.c.getSnapshot().ready).toBe(true);
  });

  it("takes any board the database has, whatever its stamp", async () => {
    const s = setup();
    await open(s);
    const theirs = session("theirs", t0 - 60_000, "u2");
    s.c.setRemote(theirs, true, false);
    const state = s.c.getSnapshot();
    expect(state.session.id).toBe("theirs");
    expect(state.hasBoard).toBe(true);
    expect(state.handed).toBe(true);
  });
});

describe("clear all", () => {
  it("clears every phase, saves it and hands it over", async () => {
    const s = setup();
    await open(s);
    s.log.now = t0 + 10;
    s.c.commitStroke(dot, false);
    s.c.selectPhase("teleop");
    s.c.commitStroke(dot, false);
    s.log.now = t0 + 20;
    s.c.clearAll();
    const { session } = s.c.getSnapshot();
    expect(session.strokes.auton).toHaveLength(0);
    expect(session.strokes.teleop).toHaveLength(0);
    await wait(1000);
    const last = s.log.sent[s.log.sent.length - 1] as {
      strokesByPhase: Record<string, unknown[]>;
    };
    expect(last.strokesByPhase.auton).toHaveLength(0);
    expect(last.strokesByPhase.teleop).toHaveLength(0);
  });
});

describe("saving", () => {
  it("saves on this device at once and hands to the outbox a second later", async () => {
    const s = setup();
    await open(s);
    s.log.now = t0 + 10;
    s.c.commitStroke(dot, false);
    await settle();
    expect(s.log.saved).toHaveLength(1);
    expect(s.log.sent).toHaveLength(0);
    expect(s.c.getSnapshot().handed).toBe(false);
    await wait(1000);
    expect(s.log.sent).toHaveLength(1);
    const doc = s.log.sent[0] as Record<string, unknown>;
    expect(doc.id).toBe("board-1");
    expect(doc.authorUid).toBe("u1");
    expect((doc.strokesByPhase as { auton: unknown[] }).auton).toHaveLength(1);
    expect(s.c.getSnapshot().handed).toBe(true);
    expect(s.log.saved.at(-1)?.queuedMs).toBe(t0 + 10);
  });

  it("records the teams on the side we are not as opponents", async () => {
    const s = setup();
    await open(s);
    s.log.now = t0 + 10;
    s.c.commitStroke(dot, false);
    await wait(1000);
    expect(s.log.sent[0]).toMatchObject({
      alliance: "Red",
      teamNumbers: [1111, 2222, 3333, 4444, 5555, 6666],
      opponentTeams: [4444, 5555, 6666],
    });
  });

  it("sends one document for a burst of changes", async () => {
    const s = setup();
    await open(s);
    s.log.now = t0 + 10;
    s.c.commitStroke(dot, false);
    await wait(400);
    s.log.now = t0 + 420;
    s.c.commitStroke(dot, false);
    await wait(1000);
    expect(s.log.sent).toHaveLength(1);
    const doc = s.log.sent[0] as Record<string, unknown>;
    const strokes = (doc.strokesByPhase as { auton: unknown[] }).auton;
    expect(strokes).toHaveLength(2);
  });

  it("finishes local saves in call order, one at a time", async () => {
    const s = setup();
    await open(s);
    for (let i = 1; i <= 4; i++) {
      s.log.now = t0 + i;
      s.c.commitStroke(dot, false);
    }
    await settle();
    expect(s.log.most).toBe(1);
    const strokeCounts = s.log.saved.map(
      (r) => (r.doc.strokesByPhase as { auton: unknown[] }).auton.length,
    );
    expect(strokeCounts).toEqual([1, 2, 3, 4]);
  });

  it("serializes each save before it is queued", async () => {
    const s = setup();
    await open(s);
    s.c.commitStroke(dot, false);
    s.c.commitStroke(dot, false);
    await settle();
    const first = s.log.saved[0]?.doc.strokesByPhase as { auton: unknown[] };
    expect(first.auton).toHaveLength(1);
  });

  it("hands a change over when told to leave", async () => {
    const s = setup();
    await open(s);
    s.c.commitStroke(dot, false);
    s.c.flush();
    expect(s.log.sent).toHaveLength(1);
    await wait(2000);
    expect(s.log.sent).toHaveLength(1);
  });

  it("reports a device that could not keep the drawing", async () => {
    const s = setup({ saveFails: true });
    await open(s);
    s.c.commitStroke(dot, false);
    await settle();
    expect(s.c.getSnapshot().local).toBe("failed");
  });

  it("does not send a stroke with no length", async () => {
    const s = setup();
    await open(s);
    s.c.commitStroke([{ x: 0.1, y: 0.1 }], false);
    await wait(2000);
    expect(s.log.saved).toHaveLength(0);
    s.c.commitStroke([{ x: 0.1, y: 0.1 }], true);
    await wait(2000);
    expect(s.log.sent).toHaveLength(1);
  });

  it("waits for sign-in before it sends", async () => {
    const s = setup();
    s.c.setAuthor({ uid: "", displayName: "" });
    await open(s);
    s.c.commitStroke(dot, false);
    await wait(2000);
    expect(s.log.sent).toHaveLength(0);
    expect(s.c.getSnapshot().handed).toBe(false);
    s.c.setAuthor(lead);
    await wait(10);
    expect(s.log.sent).toHaveLength(1);
    expect(s.log.sent[0]?.authorUid).toBe("u1");
  });

  it("keeps the first author on later sends", async () => {
    const s = setup();
    await open(s);
    s.c.commitStroke(dot, false);
    s.c.flush();
    s.c.setAuthor({ uid: "u2", displayName: "Lead B" });
    s.log.now = t0 + 5000;
    s.c.commitStroke(dot, false);
    s.c.flush();
    expect(s.log.sent[1]?.authorUid).toBe("u1");
  });
});

describe("reopening", () => {
  it("opens this device's copy", async () => {
    const mine = session("board-1", t0);
    const s = setup({ record: recordOf(mine, t0) });
    await open(s);
    expect(s.c.getSnapshot().session.id).toBe("board-1");
    expect(s.c.getSnapshot().hasBoard).toBe(true);
    await wait(3000);
    expect(s.log.sent).toHaveLength(0);
  });

  it("hands over a change that was saved but not yet sent", async () => {
    const mine = session("board-1", t0 + 500);
    const s = setup({ record: recordOf(mine, t0) });
    await open(s);
    await wait(10);
    expect(s.log.sent).toHaveLength(1);
  });
});

describe("another device's version", () => {
  const mine = () => session("board-1", t0);

  it("ignores this device's own write coming back", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    s.c.setRemote({ ...mine(), id: "board-1" }, true, false);
    expect(s.c.getSnapshot().conflict).toBeNull();
    expect(s.discard).not.toHaveBeenCalled();
  });

  it("replaces a clean board with a newer one", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    const theirs = session("board-1", t0 + 5000, "u2");
    s.c.setRemote(theirs, true, false);
    expect(s.c.getSnapshot().session.updatedMs).toBe(t0 + 5000);
    expect(s.c.getSnapshot().conflict).toBeNull();
    expect(s.discard).toHaveBeenCalled();
    await wait(2000);
    expect(s.log.sent).toHaveLength(0);
  });

  it("waits for a stroke in progress, then takes it", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    s.c.setDrawing(true);
    s.c.setRemote(session("board-1", t0 + 5000, "u2"), true, false);
    expect(s.c.getSnapshot().session.updatedMs).toBe(t0);
    s.c.setDrawing(false);
    expect(s.c.getSnapshot().session.updatedMs).toBe(t0 + 5000);
  });

  it("asks when this device has changes the database does not", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    s.log.now = t0 + 100;
    s.c.commitStroke(dot, false);
    s.c.setRemote(session("board-1", t0 + 5000, "u2"), true, false);
    expect(s.c.getSnapshot().conflict?.updatedMs).toBe(t0 + 5000);
    await wait(3000);
    expect(s.log.sent).toHaveLength(0);
    s.c.commitStroke(dot, false);
    await settle();
    expect(s.log.saved.length).toBeGreaterThan(1);
    expect(s.log.sent).toHaveLength(0);
  });

  it("asks when an earlier send is still unconfirmed", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    s.log.unsent.add("board-1");
    await open(s);
    s.c.setRemote(session("board-1", t0 + 5000, "u2"), true, false);
    expect(s.c.getSnapshot().conflict).not.toBeNull();
  });

  it("asks on open when an earlier send is still unconfirmed", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    s.log.unsent.add("board-1");
    await open(s, session("board-1", t0 + 5000, "u2"));
    expect(s.c.getSnapshot().conflict).not.toBeNull();
    expect(s.c.getSnapshot().session.updatedMs).toBe(t0);
    expect(s.discard).not.toHaveBeenCalled();
  });

  it("drops the unsent items of the board it leaves, not of the one it takes", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    s.c.setRemote(session("theirs", t0 + 5000, "u2"), true, false);
    expect(s.c.getSnapshot().session.id).toBe("theirs");
    expect(s.discard).toHaveBeenCalledWith("board-1");
  });

  it("keeps this device's version by stamping it past theirs and sending it", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    s.log.now = t0 + 100;
    s.c.commitStroke(dot, false);
    s.c.setRemote(session("board-1", t0 + 5000, "u2"), true, false);
    s.c.keepMine();
    expect(s.c.getSnapshot().conflict).toBeNull();
    expect(s.log.sent).toHaveLength(1);
    expect(s.log.sent[0]?.updatedAt).toBe(new Date(t0 + 5001).toISOString());
    expect(s.c.getSnapshot().session.strokes.auton).toHaveLength(1);
  });

  it("takes theirs and drops this device's unsent changes", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s);
    s.log.now = t0 + 100;
    s.c.commitStroke(dot, false);
    s.c.setRemote(session("board-1", t0 + 5000, "u2"), true, false);
    s.c.loadTheirs();
    const state = s.c.getSnapshot();
    expect(state.conflict).toBeNull();
    expect(state.session.strokes.auton).toHaveLength(0);
    expect(state.session.updatedMs).toBe(t0 + 5000);
    expect(s.discard).toHaveBeenCalled();
    await wait(3000);
    expect(s.log.sent).toHaveLength(0);
  });

  it("opens with the choice when the saved copy has unsent changes", async () => {
    const edited = session("board-1", t0 + 500);
    const s = setup({ record: recordOf(edited, t0) });
    await open(s, session("board-1", t0 + 5000, "u2"));
    expect(s.c.getSnapshot().conflict).not.toBeNull();
    await wait(3000);
    expect(s.log.sent).toHaveLength(0);
  });

  it("opens on the newer version when the saved copy is all sent", async () => {
    const s = setup({ record: recordOf(mine(), t0) });
    await open(s, session("board-1", t0 + 5000, "u2"));
    expect(s.c.getSnapshot().session.updatedMs).toBe(t0 + 5000);
    expect(s.c.getSnapshot().conflict).toBeNull();
  });
});

describe("robots", () => {
  it("places the chosen robot and moves on to the next one", async () => {
    const s = setup();
    await open(s);
    s.c.selectTool("robot");
    expect(s.c.getSnapshot().team).toBe(1111);
    s.c.placeAt({ x: 0.2, y: 0.2 });
    expect(s.c.getSnapshot().team).toBe(2222);
    s.c.selectTeam(5555);
    s.c.placeAt({ x: 0.8, y: 0.8 });
    const markers = s.c.getSnapshot().session.markers.auton;
    expect(markers.map((m) => [m.team, m.alliance])).toEqual([
      [1111, "Red"],
      [5555, "Blue"],
    ]);
    expect(s.c.getSnapshot().team).toBe(2222);
  });

  it("starts each phase on the first robot not yet there", async () => {
    const s = setup();
    await open(s);
    s.c.placeAt({ x: 0.2, y: 0.2 });
    s.c.selectPhase("teleop");
    expect(s.c.getSnapshot().team).toBe(1111);
  });

  it("places nothing once all six are down", async () => {
    const s = setup();
    await open(s);
    s.c.placeAll();
    expect(s.c.getSnapshot().team).toBeNull();
    s.c.placeAt({ x: 0.5, y: 0.5 });
    expect(s.c.getSnapshot().session.markers.auton).toHaveLength(6);
  });

  it("writes the phase, tool and robot the lead was on", async () => {
    const s = setup();
    await open(s);
    s.c.selectPhase("endgame");
    s.c.selectTool("robot");
    s.c.placeAt({ x: 0.5, y: 0.5 });
    await settle();
    expect(s.log.saved.at(-1)?.doc).toMatchObject({
      selectedPhase: "endgame",
      selectedTool: "robot",
      selectedRobotTeam: 2222,
    });
  });
});

describe("moving a team to the other side", () => {
  it("moves it, keeps the roster in step, saves and hands it over", async () => {
    const s = setup();
    await open(s);
    s.c.setPractice(true);
    s.log.now = t0 + 10;
    s.c.moveTeamSide(2222);
    const state = s.c.getSnapshot();
    expect(state.session.opponentTeams).toEqual([2222, 4444, 5555, 6666]);
    expect(
      state.robots.filter((r) => r.side === "blue").map((r) => r.team),
    ).toEqual([2222, 4444, 5555, 6666]);
    expect(state.robots.find((r) => r.team === 2222)?.side).toBe("blue");
    await wait(1000);
    expect(s.log.saved.at(-1)?.doc).toMatchObject({
      opponentTeams: [2222, 4444, 5555, 6666],
    });
    expect(s.log.sent).toHaveLength(1);
    expect(s.log.sent[0]).toMatchObject({
      id: "board-1",
      opponentTeams: [2222, 4444, 5555, 6666],
      teamNumbers: [1111, 2222, 3333, 4444, 5555, 6666],
    });
  });

  it("places the moved team on its new side", async () => {
    const s = setup();
    await open(s);
    s.c.setPractice(true);
    s.c.moveTeamSide(1111);
    s.c.selectTool("robot");
    s.c.selectTeam(1111);
    s.c.placeAt({ x: 0.5, y: 0.5 });
    expect(s.c.getSnapshot().session.markers.auton[0]).toMatchObject({
      team: 1111,
      alliance: "Blue",
    });
  });

  it("does nothing on a scheduled board", async () => {
    const s = setup();
    await open(s);
    s.c.moveTeamSide(1111);
    await wait(5000);
    expect(s.c.getSnapshot().session.opponentTeams).toEqual([4444, 5555, 6666]);
    expect(s.c.getSnapshot().robots).toEqual(robots);
    expect(s.log.sent).toHaveLength(0);
  });
});
