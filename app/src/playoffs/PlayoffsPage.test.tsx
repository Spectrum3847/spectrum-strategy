// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { ready, setRoles } from "../auth/rolesMock";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { parseBoard } from "./board";
import { Playoffs } from "./PlayoffsPage";
import type { RemoteState } from "./remote";

const config = parseConfig(bundled);

const idleRemote = {
  shared: null,
  ready: true,
  failed: false,
  fromCache: false,
};

const state = vi.hoisted(() => ({
  eventKey: "2027test",
  entries: [] as unknown[],
  remote: null as unknown as RemoteState,
  outbox: [] as unknown[],
  sent: [] as unknown[][],
}));

vi.mock("./remote", () => ({
  useRemoteBoard: () => state.remote,
  sendBoard: (...args: unknown[]) => {
    state.sent.push(args);
    return Promise.resolve("id");
  },
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../outbox/outbox", () => ({
  enqueueWrite: vi.fn(),
  getOutbox: () => [],
  subscribeOutbox: () => () => undefined,
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
    eventReady: true,
    schedule: [],
  }),
}));
vi.mock("../teams/useTeamData", () => ({
  useTeamData: () => ({
    eventKey: state.eventKey,
    eventReady: true,
    tba: {
      teams: [{ number: 1111, nickname: "Alpha" }],
      rankings: [],
      matches: [
        {
          key: "2027test_qm1",
          level: "qm",
          red: [],
          blue: [],
          redScore: null,
          blueScore: null,
          winner: null,
        },
        {
          key: "2027test_qm2",
          level: "qm",
          red: [],
          blue: [],
          redScore: null,
          blueScore: null,
          winner: null,
        },
      ],
    },
    entries: { items: state.entries, ready: true, failed: false },
    epa: { status: "ready", data: null },
    taken: new Map(),
    rows: [
      {
        team: 1111,
        nickname: "Alpha",
        listed: true,
        rank: 4,
        record: "",
        epa: null,
        matches: 2,
        total: 30,
        auto: 5,
        teleop: 25,
        iqm: { total: 30, auto: 5, teleop: 25 },
        mean: { total: 30, auto: 5, teleop: 25 },
        sd: null,
        form: null,
        climb: 0,
        series: [],
      },
      {
        team: 2222,
        nickname: "Beta",
        listed: true,
        rank: null,
        record: "",
        epa: null,
        matches: 1,
        total: 10,
        auto: 2,
        teleop: 8,
        iqm: { total: 10, auto: 2, teleop: 8 },
        mean: { total: 10, auto: 2, teleop: 8 },
        sd: null,
        form: null,
        climb: 0,
        series: [],
      },
    ],
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
vi.mock("./videos", () => ({
  useQualVideos: () => ({
    status: "ready",
    videos: { "2027test_qm1": "https://www.youtube.com/watch?v=abc123XYZ" },
  }),
}));
vi.mock("../assistant/AiRewrite", () => ({ AiRewrite: () => null }));

const card: EventEntry = {
  id: "e1",
  tbaMatchKey: "2027test_qm1",
  teamNumber: 2222,
  alliance: "Red",
  scoutName: "Scout A",
  updatedAt: "2027-03-01T12:00:00.000Z",
  fieldValues: { ryCard: "Red" },
};

function view(path = "/picks/playoffs") {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/picks/playoffs" element={<Playoffs />} />
      </Routes>
    </MemoryRouter>,
  );
}

const stored = () =>
  JSON.parse(localStorage.getItem("ss.playoff.cache.2027test") ?? "{}").board;

const sharedBoard = (meeting: Record<string, string>, ms = 1000) => ({
  ...idleRemote,
  shared: { board: parseBoard({ meeting }), ms, by: "Lead B" },
});

const flush = () =>
  act(async () => {
    await vi.advanceTimersByTimeAsync(1000);
  });

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout", "Date"] });
  localStorage.clear();
  setRoles(ready("strategy"));
  state.eventKey = "2027test";
  state.entries = [];
  state.remote = idleRemote;
  state.outbox = [];
  state.sent = [];
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("playoff section", () => {
  it("types into the sorting board, keeps a copy and sends the whole board", async () => {
    view();
    const editedAt = Date.now();
    fireEvent.change(screen.getByLabelText("Tier 1 row 1"), {
      target: { value: "1111" },
    });
    expect(stored().meeting).toEqual({ "0,0": "1111" });
    expect(stored().version).toBe(1);
    expect(state.sent).toHaveLength(0);
    await flush();
    expect(state.sent).toHaveLength(1);
    const [eventKey, board, ms, by] = state.sent[0] as [
      string,
      { meeting: Record<string, string> },
      number,
      string,
    ];
    expect(eventKey).toBe("2027test");
    expect(board.meeting).toEqual({ "0,0": "1111" });
    expect(ms).toBe(editedAt);
    expect(by).toBe("Scout A");
  });

  it("stamps a write no earlier than the stored board", async () => {
    const later = Date.now() + 60_000;
    state.remote = sharedBoard({ "0,0": "7777" }, later);
    view();
    fireEvent.change(screen.getByLabelText("Tier 1 row 2"), {
      target: { value: "2222" },
    });
    await flush();
    expect(state.sent[0]?.[2]).toBeGreaterThanOrEqual(later);
  });

  it("shows the shared board and who changed it last", () => {
    state.remote = sharedBoard({ "0,0": "7777" });
    view();
    expect(
      (screen.getByLabelText("Tier 1 row 1") as HTMLInputElement).value,
    ).toBe("7777");
    expect(screen.getByText(/Last changed by Lead B/)).toBeTruthy();
  });

  it("keeps an unsent edit over a newer shared board", () => {
    view();
    fireEvent.change(screen.getByLabelText("Tier 1 row 1"), {
      target: { value: "1111" },
    });
    state.remote = sharedBoard({ "0,0": "7777" }, Date.now() + 5000);
    cleanup();
    view();
    expect(
      (screen.getByLabelText("Tier 1 row 1") as HTMLInputElement).value,
    ).toBe("1111");
  });

  it("renames a column", () => {
    view();
    fireEvent.change(screen.getByLabelText("Column 1 name"), {
      target: { value: "Best" },
    });
    expect(stored().labels[0]).toBe("Best");
    expect(screen.getByLabelText("Best row 1")).toBeTruthy();
  });

  it("marks the selected cell with highlight and italic", () => {
    view();
    const cell = screen.getByLabelText("Tier 1 row 1");
    fireEvent.change(cell, { target: { value: "1111" } });
    fireEvent.focus(cell);
    fireEvent.click(screen.getByRole("button", { name: "Highlight" }));
    fireEvent.click(screen.getByRole("button", { name: "Italic" }));
    expect(stored().styles["0,0"]).toEqual({ highlighted: true, italic: true });
    fireEvent.click(screen.getByRole("button", { name: "Clear cell" }));
    expect(stored().meeting).toEqual({});
    expect(stored().styles).toEqual({});
  });

  it("moves a team from the ranked list to the board by tap", () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: "Move 1111" }));
    expect(screen.getByText(/Holding 1111/)).toBeTruthy();
    fireEvent.click(
      screen.getByRole("button", { name: "Place 1111 in Tier 2 row 3" }),
    );
    expect(stored().meeting).toEqual({ "2,1": "1111" });
    expect(screen.queryByText(/Holding/)).toBeNull();
  });

  it("swaps two cells by tap and cancels with Escape", () => {
    view();
    fireEvent.change(screen.getByLabelText("Tier 1 row 1"), {
      target: { value: "1111" },
    });
    fireEvent.change(screen.getByLabelText("Tier 1 row 2"), {
      target: { value: "2222" },
    });
    fireEvent.click(
      screen.getByRole("button", { name: "Move 1111 from Tier 1 row 1" }),
    );
    fireEvent.click(
      screen.getByRole("button", {
        name: "Place the held cell in Tier 1 row 2",
      }),
    );
    expect(stored().meeting).toEqual({ "0,0": "2222", "1,0": "1111" });
    fireEvent.click(
      screen.getByRole("button", { name: "Move 2222 from Tier 1 row 1" }),
    );
    fireEvent.keyDown(window, { key: "Escape" });
    expect(screen.queryByText(/Holding a cell/)).toBeNull();
  });

  it("lists tank, carded teams and qualification video", () => {
    state.entries = [card];
    view();
    expect(
      screen.getByText("No tank drivetrain teams pit scouted."),
    ).toBeTruthy();
    expect(
      screen.getByRole("region", { name: "Yellow or red card" }),
    ).toBeTruthy();
    expect(screen.getByRole("link", { name: "Watch Q1" })).toBeTruthy();
    expect(screen.getByText("No video")).toBeTruthy();
  });

  it("shows the next three teams, with a card, until they are placed", () => {
    state.entries = [card];
    view("/picks/playoffs?part=alliances");
    expect(screen.getByText(/Fill in the sorting board/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Scouting meeting" }));
    fireEvent.change(screen.getByLabelText("Tier 1 row 1"), {
      target: { value: "2222" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Alliances" }));
    expect(screen.getByRole("article", { name: "Team 2222" })).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Alliance 1 Captain"), {
      target: { value: "2222" },
    });
    expect(screen.queryByRole("article", { name: "Team 2222" })).toBeNull();
    expect(screen.getByText(/Every team on the sorting board/)).toBeTruthy();
    expect(screen.getAllByText("Red card").length).toBeGreaterThan(0);
  });

  it("offers a board saved before boards synced, and uploads it", async () => {
    localStorage.setItem(
      "ss.playoff.2027test",
      JSON.stringify({ version: 1, meeting: { "0,0": "7777" } }),
    );
    view();
    expect(screen.getByText(/from before boards were shared/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Upload this board" }));
    expect(screen.queryByText(/from before boards were shared/)).toBeNull();
    expect(localStorage.getItem("ss.playoff.2027test")).toBeNull();
    await flush();
    const board = state.sent[0]?.[1] as
      | { meeting: Record<string, string> }
      | undefined;
    expect(board?.meeting).toEqual({ "0,0": "7777" });
  });

  it("drops a saved board when the lead discards it", () => {
    localStorage.setItem(
      "ss.playoff.2027test",
      JSON.stringify({ version: 1, meeting: { "0,0": "7777" } }),
    );
    view();
    fireEvent.click(screen.getByRole("button", { name: "Discard it" }));
    expect(localStorage.getItem("ss.playoff.2027test")).toBeNull();
    expect(state.sent).toHaveLength(0);
  });

  it("clears a saved board the database already holds", () => {
    localStorage.setItem(
      "ss.playoff.2027test",
      JSON.stringify({ version: 1, meeting: { "0,0": "7777" } }),
    );
    state.remote = sharedBoard({ "0,0": "7777" });
    view();
    expect(screen.queryByText(/from before boards were shared/)).toBeNull();
    expect(localStorage.getItem("ss.playoff.2027test")).toBeNull();
  });

  it("waits for the database before offering a saved board", () => {
    localStorage.setItem(
      "ss.playoff.2027test",
      JSON.stringify({ version: 1, meeting: { "0,0": "7777" } }),
    );
    state.remote = { ...idleRemote, ready: false };
    view();
    expect(screen.queryByText(/from before boards were shared/)).toBeNull();
    expect(localStorage.getItem("ss.playoff.2027test")).not.toBeNull();
  });

  it("gives a mentor the shared board to read and no way to change it", () => {
    setRoles(ready("mentor"));
    state.remote = sharedBoard({ "0,0": "7777" });
    view();
    const cell = screen.getByLabelText("Tier 1 row 1") as HTMLInputElement;
    expect(cell.value).toBe("7777");
    expect(cell.readOnly).toBe(true);
    fireEvent.change(cell, { target: { value: "1" } });
    expect(state.sent).toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Highlight" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Move 1111" })).toBeNull();
    expect(screen.getByRole("heading", { name: "Ranked teams" })).toBeTruthy();
    expect(screen.queryByText(/from before boards were shared/)).toBeNull();
  });

  it("asks for an event when none is set", () => {
    state.eventKey = "";
    view();
    expect(screen.getByText(/No event is set/)).toBeTruthy();
  });
});
