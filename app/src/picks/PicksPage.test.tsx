// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { ready, setRoles } from "../auth/rolesMock";
import { myTeamStore } from "../now/myTeam";
import { parseConfig } from "../scout/config";
import { forgetDrafts, getDraft, setDraft } from "./draftStore";
import { PickedMark } from "./PickedMark";
import { Picks } from "./PicksPage";
import type { PickList } from "./pickList";

const config = parseConfig(bundled);
const teams = Array.from({ length: 12 }, (_, i) => 1001 + i);

const state = vi.hoisted(() => ({
  lists: [] as unknown[],
  failed: false,
  eventKey: "2027test",
  eventReady: true,
  entriesReady: true,
  entries: [] as unknown[],
  outbox: [] as unknown[],
  save: vi.fn((..._args: unknown[]) => Promise.resolve("id")),
  dismiss: vi.fn((_id: string) => undefined),
  remove: vi.fn((..._args: unknown[]) => Promise.resolve("o1")),
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: "signed-in", uid: "u1", displayName: "Lead A" }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({
    config,
    eventKey: state.eventKey,
    eventReady: state.eventReady,
    schedule: [],
  }),
}));
vi.mock("../data/useCorrections", () => ({
  useCorrections: () => ({ items: [], ready: true, failed: false }),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({
    items: state.entries,
    ready: state.entriesReady,
    failed: false,
  }),
}));
vi.mock("../data/useCollections", async () => {
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const { parseConfig: parse } = await import("../scout/config");
  return {
    usePitEntries: () => ({ items: [], ready: true, failed: false }),
    useFormConfig: () => parse(pit.default),
  };
});
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027test",
    status: "ready",
    fetchedAt: "2027-03-01T12:00:00.000Z",
    teams: teams.map((number) => ({ number, nickname: `Bots ${number}` })),
    rankings: teams.map((team, i) => ({
      team,
      rank: i + 1,
      wins: 0,
      losses: 0,
      ties: 0,
    })),
    matches: [],
  }),
}));
vi.mock("../match/useOutside", () => ({
  useEpa: () => ({ status: "ready", data: null }),
}));
vi.mock("./eventType", () => ({
  useEventKind: () => ({ type: 1, name: "District" }),
}));
vi.mock("./usePickLists", () => ({
  usePickLists: () => ({
    items: state.lists,
    ready: true,
    failed: state.failed,
  }),
  savePickList: (...args: unknown[]) => state.save(...args),
  pickListPath: (id: string) => `pickLists/${id}`,
  lastWrittenMs: () => 0,
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../outbox/outbox", () => ({
  dismissItem: (id: string) => state.dismiss(id),
  enqueueDelete: (...args: unknown[]) => state.remove(...args),
}));

const list = (over: Partial<PickList> = {}): PickList => ({
  id: "l1",
  name: "Quals",
  teamNumbers: [1005, 1006, 1007],
  tiers: [
    { name: "1st pick", teams: [1005, 1006] },
    { name: "2nd pick", teams: [1007] },
  ],
  dnp: [{ team: 1012, reason: "Died twice" }],
  authorUid: "u1",
  authorDisplayName: "Lead A",
  updatedMs: 1_800_000_000_000,
  ...over,
});

function view(path = "/picks") {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/picks" element={<Picks />} />
      </Routes>
    </MemoryRouter>,
  );
}

const saved = () => state.save.mock.calls[0]?.[0] as PickList;

beforeEach(() => {
  localStorage.clear();
  forgetDrafts();
  myTeamStore.reload();
  setRoles(ready("strategy"));
  state.lists = [list()];
  state.failed = false;
  state.eventKey = "2027test";
  state.eventReady = true;
  state.entriesReady = true;
  state.entries = [];
  state.outbox = [];
  state.save.mockClear();
  state.dismiss.mockClear();
  state.remove.mockClear();
});
afterEach(cleanup);

describe("deleting a pick list", () => {
  it("asks first, then deletes the list through the outbox", async () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: /^Delete pick list/ }));
    expect(state.remove).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: /^Confirm delete/ }));
    await waitFor(() =>
      expect(state.remove).toHaveBeenCalledWith(
        "pickLists/l1",
        expect.any(String),
      ),
    );
  });

  it("offers no delete to a mentor", () => {
    setRoles(ready("mentor"));
    view();
    expect(screen.queryByRole("button", { name: /^Delete/ })).toBeNull();
  });
});

describe("pick list", () => {
  it("waits for scout entries before calling teams unscouted", () => {
    state.entriesReady = false;
    view();
    expect(screen.getByText("Loading event and scouting data.")).toBeTruthy();
    expect(screen.queryByText(/Not scouted/)).toBeNull();
  });
  it("waits for the event before claiming none is set", () => {
    state.eventKey = "";
    state.eventReady = false;
    view();
    expect(screen.getByText("Loading event and scouting data.")).toBeTruthy();
    expect(
      screen.queryByText(/No event is set|No teams are loaded/),
    ).toBeNull();
  });
  it("shows the tiers with their teams, the do-not-pick list and the pool", () => {
    view();
    const first = screen.getByRole("region", { name: /1st pick/ });
    expect(within(first).getAllByRole("listitem")).toHaveLength(2);
    expect(within(first).getByText("1005")).toBeTruthy();
    expect(screen.getByRole("region", { name: /2nd pick/ })).toBeTruthy();
    expect(screen.getByText("Died twice")).toBeTruthy();
    const pool = screen.getByRole("region", { name: /Not ranked/ });
    expect(within(pool).getByRole("heading", { name: /\(8\)/ })).toBeTruthy();
    expect(within(pool).queryByText("1005")).toBeNull();
  });

  it("shows each team's key stats", () => {
    view();
    const first = screen.getByRole("region", { name: /1st pick/ });
    expect(within(first).getByText("Not scouted · Rank 5")).toBeTruthy();
  });

  it("moves a team with the buttons and saves the flattened list", () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: "Move 1005 down" }));
    const next = saved();
    expect(next.tiers[0]?.teams).toEqual([1006, 1005]);
    expect(next.teamNumbers).toEqual([1006, 1005, 1007]);
    expect(next.authorUid).toBe("u1");
    expect(next.updatedMs).toBeGreaterThanOrEqual(1_800_000_000_000);
  });

  it("moves a team across tiers from the keyboard", () => {
    view();
    fireEvent.keyDown(screen.getByRole("button", { name: "Reorder 1006" }), {
      key: "ArrowRight",
    });
    expect(saved().tiers.map((t) => t.teams)).toEqual([[1005], [1007, 1006]]);
  });

  it("adds a pool team to a tier", () => {
    view();
    fireEvent.change(screen.getByLabelText("Add 1001 to a tier"), {
      target: { value: "1" },
    });
    expect(saved().tiers[1]?.teams).toEqual([1007, 1001]);
  });

  it("asks for a reason before a team goes on do not pick", () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: "More for 1005" }));
    fireEvent.click(screen.getByRole("button", { name: "Do not pick" }));
    fireEvent.click(screen.getByRole("button", { name: "Do not pick" }));
    expect(screen.getByRole("alert").textContent).toMatch(/Say why/);
    expect(state.save).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText("Why not 1005"), {
      target: { value: "Red card Q9" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Do not pick" }));
    const next = saved();
    expect(next.dnp).toContainEqual({ team: 1005, reason: "Red card Q9" });
    expect(next.teamNumbers).toEqual([1006, 1007]);
  });

  it("counts likely teams, confirms what was added, and says when there are none", () => {
    const entry = (id: string, team: number, n: number, values: object) => ({
      id,
      teamNumber: team,
      alliance: "Red",
      tbaMatchKey: `2027test_qm${n}`,
      scoutName: "Scout A",
      updatedAt: "2027-03-01T10:00:00.000Z",
      fieldValues: values,
    });
    state.entries = [
      entry("a", 1008, 1, { ryCard: "Red" }),
      entry("b", 1009, 2, { dieCard: true }),
      entry("c", 1009, 3, { dieCard: true }),
      entry("d", 1010, 4, { ryCard: "Yellow" }),
    ];
    view();
    fireEvent.click(screen.getByRole("button", { name: "Add likely (2)" }));
    expect(saved().dnp.map((d) => d.team)).toEqual([1012, 1008, 1009]);
    expect(
      screen.getByText("Added 2 to do not pick: 1008, 1009."),
    ).toBeTruthy();
    cleanup();
    state.entries = [entry("d", 1010, 4, { ryCard: "Yellow" })];
    view();
    expect(screen.queryByRole("button", { name: /^Add likely/ })).toBeNull();
    expect(screen.getByText(/^No likely teams/)).toBeTruthy();
  });

  it("refuses a team that is not at the event", () => {
    view();
    fireEvent.click(
      screen.getByRole("button", { name: "Options for 1st pick" }),
    );
    fireEvent.change(screen.getByLabelText("Add a team"), {
      target: { value: "9999" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    expect(screen.getByRole("alert").textContent).toMatch(/not at this event/);
    expect(state.save).not.toHaveBeenCalled();
  });

  it("creates a list with no tiers", () => {
    state.lists = [];
    view();
    expect(screen.getByText(/No pick lists yet/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "New list" }));
    fireEvent.click(screen.getByRole("button", { name: "Create list" }));
    const made = saved();
    expect(made).toMatchObject({
      name: "Pick list",
      tiers: [],
      teamNumbers: [],
      authorUid: "u1",
    });
  });
});

describe("teams too close to call", () => {
  const scored = (team: number, values: number[]) =>
    values.map((n, i) => ({
      id: `${team}-${i}`,
      tbaMatchKey: `2027test_qm${i + 1}`,
      teamNumber: team,
      alliance: "Red",
      scoutName: "Scout A",
      updatedAt: "2027-03-01T12:00:00.000Z",
      fieldValues: { teleopFuelScored: n },
    }));

  beforeEach(() => {
    state.entries = [
      ...scored(1005, [10, 20, 30, 40]),
      ...scored(1006, [12, 22, 28, 38]),
      ...scored(1007, [100, 110, 90, 105]),
    ];
  });

  it("shows the score with its ± and marks a team tied with the one above", () => {
    view();
    const first = screen.getByRole("region", { name: /1st pick/ });
    expect(
      within(first).getByText("Score 25 ±6.5 (n=4) · Rank 5"),
    ).toBeTruthy();
    expect(within(first).getAllByText(/≈ tied with/)).toHaveLength(1);
    const rows = within(first).getAllByRole("listitem");
    expect(within(rows[0] as HTMLElement).queryByText(/≈ tied/)).toBeNull();
    expect(
      within(rows[1] as HTMLElement).getByText("≈ tied with 1005"),
    ).toBeTruthy();
  });

  it("marks nothing for a team clear of the one above it", () => {
    view();
    const second = screen.getByRole("region", { name: /2nd pick/ });
    expect(within(second).queryByText(/≈ tied/)).toBeNull();
  });

  it("shows the same mark to a mentor", () => {
    setRoles(ready("mentor"));
    view();
    expect(screen.getByText("≈ tied with 1005")).toBeTruthy();
  });

  it("compares with the team above even across a tier boundary", () => {
    state.lists = [
      list({
        tiers: [
          { name: "1st pick", teams: [1005] },
          { name: "2nd pick", teams: [1006] },
        ],
        teamNumbers: [1005, 1006],
      }),
    ];
    view();
    const second = screen.getByRole("region", { name: /2nd pick/ });
    expect(within(second).getByText("≈ tied with 1005")).toBeTruthy();
  });
});

describe("pick list for a mentor", () => {
  beforeEach(() => setRoles(ready("mentor")));

  it("shows the tiers, the teams and the do-not-pick list", () => {
    view();
    const first = screen.getByRole("region", { name: /1st pick/ });
    expect(within(first).getAllByRole("listitem")).toHaveLength(2);
    expect(within(first).getByText("1005")).toBeTruthy();
    expect(within(first).getByText("Not scouted · Rank 5")).toBeTruthy();
    expect(screen.getByRole("region", { name: /2nd pick/ })).toBeTruthy();
    expect(screen.getByText("Died twice")).toBeTruthy();
    expect(screen.getByText(/read the pick lists but not change/)).toBeTruthy();
  });

  it("has no control that changes the list", () => {
    view();
    for (const name of [
      /^Move /,
      /^Reorder /,
      /^More for /,
      /^Options for /,
      /^Add /,
      /^Remove /,
      "New list",
      "Rename list",
      "Add tier",
    ]) {
      expect(screen.queryByRole("button", { name }), String(name)).toBeNull();
    }
    expect(screen.queryByRole("region", { name: /Not ranked/ })).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(state.save).not.toHaveBeenCalled();
  });

  it("says there is nothing yet without offering to create a list", () => {
    state.lists = [];
    view();
    expect(screen.getByText("No pick lists yet.")).toBeTruthy();
    expect(screen.queryByText(/Create one/)).toBeNull();
  });
});

describe("pointer drag", () => {
  const stubPointer = (zone: Element | null) => {
    Object.defineProperty(document, "elementFromPoint", {
      configurable: true,
      value: () => zone,
    });
    HTMLElement.prototype.setPointerCapture = vi.fn();
    window.scrollBy = vi.fn();
  };
  const drag = (handle: HTMLElement, zone: Element | null, y: number) => {
    stubPointer(zone);
    fireEvent.pointerDown(handle, { pointerId: 1, button: 0 });
    fireEvent.pointerMove(handle, { pointerId: 1, clientX: 5, clientY: y });
    fireEvent.pointerUp(handle, { pointerId: 1 });
  };

  it("drops a team into another tier below its rows", () => {
    view();
    drag(
      screen.getByRole("button", { name: "Reorder 1005" }),
      screen.getByRole("region", { name: /2nd pick/ }),
      10,
    );
    expect(saved().tiers.map((t) => t.teams)).toEqual([[1006], [1007, 1005]]);
  });

  it("takes a ranked team off the list when it is dropped on Not ranked", () => {
    view();
    drag(
      screen.getByRole("button", { name: "Reorder 1005" }),
      screen.getByRole("region", { name: /Not ranked/ }),
      10,
    );
    expect(saved().teamNumbers).toEqual([1006, 1007]);
    expect(saved().tiers.flatMap((t) => t.teams)).not.toContain(1005);
  });

  it("does nothing for a press with no move", () => {
    view();
    stubPointer(null);
    const handle = screen.getByRole("button", { name: "Reorder 1005" });
    fireEvent.pointerDown(handle, { pointerId: 1, button: 0 });
    fireEvent.pointerUp(handle, { pointerId: 1 });
    expect(state.save).not.toHaveBeenCalled();
  });

  it("does nothing when released outside any tier", () => {
    view();
    drag(screen.getByRole("button", { name: "Reorder 1005" }), null, 10);
    expect(state.save).not.toHaveBeenCalled();
  });
});

describe("honest states", () => {
  it("says a newer version arrived from somewhere else", () => {
    const { rerender } = render(
      <MemoryRouter initialEntries={["/picks"]}>
        <Routes>
          <Route path="/picks" element={<Picks />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(screen.queryByText(/saved a newer version/)).toBeNull();
    state.lists = [
      list({
        updatedMs: 1_800_000_060_000,
        tiers: [
          { name: "1st pick", teams: [1006, 1005] },
          { name: "2nd pick", teams: [1007] },
        ],
      }),
    ];
    rerender(
      <MemoryRouter initialEntries={["/picks"]}>
        <Routes>
          <Route path="/picks" element={<Picks />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(screen.getByText(/saved a newer version/)).toBeTruthy();
    expect(
      within(screen.getByRole("region", { name: /1st pick/ })).getAllByRole(
        "listitem",
      )[0]?.textContent,
    ).toContain("1006");
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));
    expect(screen.queryByText(/saved a newer version/)).toBeNull();
  });

  it("says a change is on this device until the database has it", () => {
    state.outbox = [
      { id: "o1", path: "pickLists/l1", status: "on-device", data: {} },
    ];
    view();
    expect(screen.getByText("On this device")).toBeTruthy();
  });

  it("says another lead saved a newer version when a write is refused behind it", () => {
    state.outbox = [
      {
        id: "o1",
        path: "pickLists/l1",
        status: "refused",
        data: { updatedAtTs: { __ts: [1_700_000_000, 0] } },
        error: "denied",
      },
    ];
    view();
    expect(screen.getByRole("alert").textContent).toMatch(/newer version/);
    fireEvent.click(screen.getByRole("button", { name: "Discard my change" }));
    expect(state.dismiss).toHaveBeenCalledWith("o1");
  });

  it("does not blame another lead for any other refusal", () => {
    state.outbox = [
      {
        id: "o1",
        path: "pickLists/l1",
        status: "refused",
        data: { updatedAtTs: { __ts: [1_900_000_000, 0] } },
      },
    ];
    view();
    expect(screen.getByRole("alert").textContent).not.toMatch(/newer version/);
    expect(screen.getByRole("alert").textContent).toMatch(/refused/);
  });

  it("says when it is offline and showing what the device last saved", () => {
    const online = vi.spyOn(navigator, "onLine", "get").mockReturnValue(false);
    view();
    expect(
      screen.getByText(/Offline\. This shows what this device last saved/),
    ).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Quals" })).toBeTruthy();
    online.mockRestore();
  });

  it("says when the latest lists could not be read", () => {
    state.failed = true;
    view();
    expect(
      screen.getByText(/Could not read the latest pick lists/),
    ).toBeTruthy();
  });
});

describe("draft board", () => {
  it("shows eight alliances and who is on the clock", () => {
    view("/picks?view=draft");
    expect(
      screen.getByRole("heading", { name: "Alliance 1 is on the clock" }),
    ).toBeTruthy();
    expect(
      within(screen.getByRole("list", { name: "Alliances" })).getAllByRole(
        "listitem",
      ),
    ).toHaveLength(8);
    expect(screen.getByText("On the clock")).toBeTruthy();
    expect(
      screen.getByText(/set from the event type \(District\)/),
    ).toBeTruthy();
    expect(
      screen
        .getByRole("button", { name: "2 rounds" })
        .getAttribute("aria-pressed"),
    ).toBe("true");
  });

  it("records a pick, moves the clock, and undoes it", () => {
    view("/picks?view=draft");
    fireEvent.click(screen.getByRole("button", { name: "1009 accepted" }));
    expect(
      screen.getByRole("heading", { name: "Alliance 2 is on the clock" }),
    ).toBeTruthy();
    const first = screen.getByRole("list", { name: "Alliances" }).children[0];
    expect(within(first as HTMLElement).getByText("1009")).toBeTruthy();
    expect(
      JSON.parse(localStorage.getItem("ss.draft.v1.2027test") ?? "{}").taken,
    ).toMatchObject({
      "1009": "Picked by alliance 1",
    });
    fireEvent.click(screen.getByRole("button", { name: "Undo pick of 1009" }));
    expect(
      screen.getByRole("heading", { name: "Alliance 1 is on the clock" }),
    ).toBeTruthy();
  });

  it("keeps a decline out of the next pick and resets with an undo", () => {
    view("/picks?view=draft");
    fireEvent.click(screen.getByRole("button", { name: "1009 declined" }));
    expect(screen.queryByRole("button", { name: "1009 accepted" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Reset" }));
    expect(screen.getByRole("button", { name: "1009 accepted" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Undo reset" }));
    expect(screen.queryByRole("button", { name: "1009 accepted" })).toBeNull();
  });

  it("says how many picks until we are on the clock", () => {
    myTeamStore.set(1003);
    view("/picks?view=draft");
    expect(screen.getByText("We pick in 2 picks.")).toBeTruthy();
  });

  it("greys a team the draft took on the pick list", () => {
    view("/picks?view=draft");
    fireEvent.click(screen.getByRole("button", { name: "1009 accepted" }));
    cleanup();
    state.lists = [
      list({
        teamNumbers: [1009],
        tiers: [{ name: "1st pick", teams: [1009] }],
      }),
    ];
    view();
    expect(screen.getByText("Picked by alliance 1")).toBeTruthy();
  });
});

describe("PickedMark", () => {
  it("says where the draft took a team and says nothing for another", () => {
    setDraft("2027test", {
      ...getDraft("2027test"),
      taken: { 1009: "Picked by alliance 3" },
    });
    render(
      <>
        <PickedMark team={1009} />
        <span data-testid="other">
          <PickedMark team={1010} />
        </span>
      </>,
    );
    expect(screen.getByText("Picked by alliance 3")).toBeTruthy();
    expect(screen.getByTestId("other").textContent).toBe("");
  });

  it("reads the log kept on this device after a reload", () => {
    localStorage.setItem(
      "ss.draft.v1.2027test",
      JSON.stringify({
        actions: [],
        rounds: 2,
        taken: { 1009: "Captain of alliance 1" },
      }),
    );
    render(<PickedMark team={1009} />);
    expect(screen.getByText("Captain of alliance 1")).toBeTruthy();
  });

  it("shows nothing when no draft was recorded", () => {
    const { container } = render(<PickedMark team={1009} />);
    expect(container.textContent).toBe("");
  });
});

describe("round 7 and 8 controls", () => {
  it("compares teams in the order ticked", () => {
    view();
    fireEvent.click(screen.getByRole("checkbox", { name: "Compare 1006" }));
    fireEvent.click(screen.getByRole("checkbox", { name: "Compare 1005" }));
    expect(
      screen.getByRole("link", { name: "Compare" }).getAttribute("href"),
    ).toBe("/teams/compare?t=1006,1005");
  });
  it("validates and records a typed draft pick", () => {
    view("/picks?view=draft");
    const input = screen.getByLabelText(
      "Team number for the alliance on the clock",
    );
    fireEvent.change(input, { target: { value: "9999" } });
    fireEvent.click(screen.getByRole("button", { name: "Record pick" }));
    expect(screen.getByRole("alert").textContent).toMatch(/event/i);
    fireEvent.change(input, { target: { value: "1009" } });
    fireEvent.click(screen.getByRole("button", { name: "Record pick" }));
    expect(getDraft("2027test").actions).toEqual([
      { team: 1009, declined: false },
    ]);
  });
});
