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
import { emptyBrief } from "./brief";
import { Match } from "./MatchPage";

const config = parseConfig(bundled);

const state = vi.hoisted(() => ({
  entries: [] as unknown[],
  entriesReady: true,
  corrections: [] as unknown[],
  pit: [] as unknown[],
  trex: [] as unknown[],
  prescout: [] as unknown[],
  teamNotes: [] as unknown[],
  briefs: [] as unknown[],
  outbox: [] as unknown[],
  epa: { status: "ready", data: null } as Record<string, unknown>,
  forecasts: { status: "ready", data: null } as Record<string, unknown>,
  matches: [] as unknown[],
  official: [] as unknown[],
  save: vi.fn((..._args: unknown[]) => Promise.resolve("id")),
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: "signed-in",
    uid: "u1",
    displayName: "Lead A",
  }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({
    config,
    eventKey: "2027test",
    schedule: [
      {
        key: "2027test_qm3",
        compLevel: "qm",
        matchNumber: 3,
        red: [1111, 2222, 3333],
        blue: [4444, 5555, 6666],
        time: 1_803_055_320,
      },
    ],
  }),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({
    items: state.entries,
    ready: state.entriesReady,
    failed: false,
  }),
}));
vi.mock("../data/useCorrections", () => ({
  useCorrections: () => ({
    items: state.corrections,
    ready: true,
    failed: false,
  }),
}));
vi.mock("../data/useCollections", async () => {
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const { parseConfig: parse } = await import("../scout/config");
  return {
    usePitEntries: () => ({ items: state.pit, ready: true, failed: false }),
    usePrescoutEntries: () => ({
      items: state.prescout,
      ready: true,
      failed: false,
    }),
    useTrexReports: () => ({ items: state.trex, ready: true, failed: false }),
    useFormConfig: () => parse(pit.default),
  };
});
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027test",
    status: "ready",
    fetchedAt: "2027-03-01T12:00:00.000Z",
    teams: [{ number: 1111, nickname: "Alpha Bots" }],
    rankings: [],
    matches: state.matches,
  }),
}));
vi.mock("../data/useTeamNotes", () => ({
  useTeamNotes: () => ({ items: state.teamNotes, ready: true, failed: false }),
}));
vi.mock("./useBriefs", () => ({
  useBriefs: () => ({ items: state.briefs, ready: true, failed: false }),
  saveBrief: (...args: unknown[]) =>
    (state.save as (...a: unknown[]) => Promise<string>)(...args),
}));
vi.mock("../reports/usePostMatchReports", () => ({
  usePostMatchReports: () => ({ items: [], ready: true, failed: false }),
  reportPath: (id: string) => `postMatchReports/${id}`,
  savePostMatchReport: () => Promise.resolve("id"),
}));
vi.mock("../accuracy/useAccuracyData", () => ({
  useOfficialCounts: () => ({
    status: "ready",
    alliances: state.official,
    fetchedAt: null,
    problem: null,
    refresh: () => {},
  }),
}));
vi.mock("./useOutside", () => ({
  useEpa: () => state.epa,
  useForecasts: () => state.forecasts,
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../board/PlanTab", () => ({
  default: (props: {
    matchKey: string;
    red: number[];
    ours: string | null;
  }) => (
    <p>
      Board for {props.matchKey}, red {props.red.join(" ")}, we are{" "}
      {props.ours ?? "not playing"}
    </p>
  ),
}));

const qm = (n: number, played: boolean, red = [1111, 2222, 3333]) => ({
  key: `2027test_qm${n}`,
  level: "qm",
  red,
  blue: [4444, 5555, 6666],
  redScore: played ? 40 : null,
  blueScore: played ? 35 : null,
  winner: played ? "red" : null,
});

const entry = (
  id: string,
  team: number,
  key: string,
  values: Record<string, unknown>,
) => ({
  id,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

function view(path = "/matches/2027test_qm3") {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/matches/:key" element={<Match />} />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(() => {
  localStorage.clear();
  myTeamStore.reload();
  setRoles(ready("strategy"));
  state.entries = [];
  state.entriesReady = true;
  state.corrections = [];
  state.pit = [];
  state.trex = [];
  state.prescout = [];
  state.teamNotes = [];
  state.briefs = [];
  state.outbox = [];
  state.epa = { status: "ready", data: null };
  state.forecasts = { status: "ready", data: null };
  state.matches = [qm(2, true), qm(3, false), qm(4, false)];
  state.official = [];
  state.save.mockClear();
});
afterEach(cleanup);

describe("match tab", () => {
  it("shows the label, the time, both alliances and our team", () => {
    myTeamStore.set(1111);
    view();
    expect(screen.getByRole("heading", { level: 1, name: "Q3" })).toBeTruthy();
    expect(screen.getByText("Upcoming")).toBeTruthy();
    expect(screen.getByText(/^2027test, Scheduled /)).toBeTruthy();
    expect(screen.getByText(/We play/)).toBeTruthy();
    expect(screen.getAllByText("us").length).toBeGreaterThan(0);
    const link = screen.getAllByRole("link", { name: "1111" })[0];
    expect(link?.getAttribute("href")).toBe("/teams/1111");
  });

  it("lists the six robots in a table, red first", () => {
    state.entries = [
      entry("a", 1111, "2027test_qm1", {
        autoFuelScored: 4,
        teleopFuelScored: 10,
        eHigh: "Successful",
      }),
    ];
    view();
    const table = screen.getByRole("table", {
      name: "Scouted stats for the six robots",
    });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(7);
    const first = within(rows[1] as HTMLElement);
    expect(first.getByRole("link", { name: "1111" })).toBeTruthy();
    expect(first.getAllByText("4").length).toBe(2);
    expect(first.getAllByText("10").length).toBe(3);
    expect(first.getByText("L3")).toBeTruthy();
    expect(within(rows[4] as HTMLElement).getByText("4444")).toBeTruthy();
    expect(screen.getByText(/Not scouted yet:/)).toBeTruthy();
  });

  it("reads a corrected value in the robot table", () => {
    state.entries = [
      entry("a", 1111, "2027test_qm1", {
        autoFuelScored: 4,
        teleopFuelScored: 10,
      }),
    ];
    state.corrections = [
      {
        id: "a",
        eventKey: "2027test",
        fields: { teleopFuelScored: 16 },
        note: "",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        updatedMs: 1,
      },
    ];
    view();
    const table = screen.getByRole("table", {
      name: "Scouted stats for the six robots",
    });
    const first = within(within(table).getAllByRole("row")[1] as HTMLElement);
    expect(first.getAllByText("16").length).toBeGreaterThan(0);
    expect(first.queryByText("10")).toBeNull();
  });

  it("shows EPA, scouting and the TBA forecast with their sources", () => {
    state.entries = [
      entry("a", 1111, "2027test_qm1", {
        autoFuelScored: 4,
        teleopFuelScored: 10,
      }),
    ];
    state.epa = { status: "ready", data: { 1111: 20, 2222: 10, 4444: 5 } };
    state.forecasts = {
      status: "ready",
      data: {
        "2027test_qm3": { redScore: 61.2, blueScore: 55.5, redWin: 0.64 },
      },
    };
    view();
    const table = screen.getByRole("table", {
      name: "Predicted score per alliance",
    });
    const epaRow = within(table).getByRole("row", { name: /Statbotics EPA/ });
    expect(within(epaRow).getByText("30.0")).toBeTruthy();
    expect(within(epaRow).getByText("5.0")).toBeTruthy();
    const scouted = within(table).getByRole("row", { name: /From scouting/ });
    expect(within(scouted).getByText("14.0")).toBeTruthy();
    const tbaRow = within(table).getByRole("row", { name: /^Forecast/ });
    expect(within(tbaRow).getByText("61.2")).toBeTruthy();
    expect(within(table).getByText("64%")).toBeTruthy();
    expect(within(table).getByText("36%")).toBeTruthy();
  });

  it("says why a prediction is missing", () => {
    view();
    expect(
      screen.getByText(/Statbotics has no EPA for this event/),
    ).toBeTruthy();
    expect(
      screen.getByText("No robot in this match has been scouted yet."),
    ).toBeTruthy();
    expect(
      screen.getByText("The Blue Alliance has no forecast for this match yet."),
    ).toBeTruthy();
  });

  it("says when Statbotics could not be reached", () => {
    state.epa = { status: "failed", data: null };
    view();
    expect(screen.getByText(/Statbotics could not be reached/)).toBeTruthy();
  });

  it("shows the result of a played match", () => {
    state.matches = [qm(3, true)];
    state.entries = [
      entry("a", 1111, "2027test_qm3", {
        autoFuelScored: 3,
        teleopFuelScored: 9,
      }),
    ];
    view();
    expect(screen.getByText("Played")).toBeTruthy();
    expect(screen.getByText("Red won")).toBeTruthy();
    expect(screen.getByText("Official 40")).toBeTruthy();
    expect(screen.getByText("Official 35")).toBeTruthy();
    expect(screen.getByText(/Scouted 12.0 from 1 of 3 robots/)).toBeTruthy();
  });

  it("shows no result for an unplayed match", () => {
    view();
    expect(screen.queryByRole("heading", { name: "Result" })).toBeNull();
  });

  it("offers the post match report for a played match only", () => {
    state.matches = [qm(3, true)];
    view();
    expect(
      screen.getByRole("heading", { name: "Post match report" }),
    ).toBeTruthy();
    cleanup();
    state.matches = [qm(3, false)];
    view();
    expect(
      screen.queryByRole("heading", { name: "Post match report" }),
    ).toBeNull();
  });

  it("shows the latest scout comment per robot", () => {
    state.entries = [
      entry("a", 1111, "2027test_qm1", { comments: "Fast intake" }),
    ];
    view();
    const section = screen
      .getByRole("heading", { name: "Latest scout comments" })
      .closest("section") as HTMLElement;
    expect(within(section).getByText("Fast intake")).toBeTruthy();
    expect(within(section).getByText("Scout A, Q1")).toBeTruthy();
  });

  it("steps to the previous and next match and keeps the open tab", () => {
    view("/matches/2027test_qm3?tab=brief");
    expect(
      screen.getByRole("link", { name: "Previous: Q2" }).getAttribute("href"),
    ).toBe("/matches/2027test_qm2?tab=brief");
    expect(
      screen.getByRole("link", { name: "Next: Q4" }).getAttribute("href"),
    ).toBe("/matches/2027test_qm4?tab=brief");
  });

  it("has no previous match at the start of the schedule", () => {
    state.matches = [qm(3, false)];
    view();
    expect(screen.queryByRole("link", { name: /^Previous/ })).toBeNull();
    expect(screen.queryByRole("link", { name: /^Next/ })).toBeNull();
  });

  it("says when the match is not on the schedule", () => {
    view("/matches/2027test_qm99");
    expect(
      screen.getByText("2027test_qm99 is not on the schedule for 2027test."),
    ).toBeTruthy();
  });
});

describe("start position clash", () => {
  const starts = (team: number, spot: string) =>
    [1, 2].map((n) =>
      entry(`${team}-${n}`, team, `2027test_qm${n}`, { starting: spot }),
    );

  it("warns when alliance mates usually start on the same spot", () => {
    state.entries = [
      ...starts(1111, "Center Hub"),
      ...starts(2222, "Center Hub"),
      ...starts(4444, "Depot Bump"),
    ];
    view();
    expect(
      screen.getByText(
        "1111 and 2222 both usually start Center Hub (2/2, 2/2)",
      ),
    ).toBeTruthy();
  });

  it("says nothing without a clash", () => {
    state.entries = [
      ...starts(1111, "Center Hub"),
      ...starts(2222, "Depot Bump"),
    ];
    view();
    expect(screen.queryByText("Start position clash")).toBeNull();
  });

  it("reads our alliance only when we play", () => {
    state.entries = [
      ...starts(4444, "Center Hub"),
      ...starts(5555, "Center Hub"),
    ];
    myTeamStore.set(1111);
    view();
    expect(screen.queryByText("Start position clash")).toBeNull();
    cleanup();
    myTeamStore.set(4444);
    view();
    expect(screen.getByText("Start position clash")).toBeTruthy();
  });
});

describe("what if", () => {
  const scouted = (team: number, auto: number, teleop: number) =>
    [0, 1, 2].map((n) =>
      entry(`${team}-${n}`, team, `2027test_qm${n + 1}`, {
        autoFuelScored: auto + n,
        teleopFuelScored: teleop + n * 2,
      }),
    );

  it("starts from this match's six teams and moves when one changes", () => {
    state.entries = [
      ...scouted(1111, 10, 40),
      ...scouted(4444, 2, 5),
      ...scouted(7777, 20, 80),
    ];
    view();
    const section = within(screen.getByRole("region", { name: "What if" }));
    expect(
      (section.getByLabelText("Red team 1") as HTMLInputElement).value,
    ).toBe("1111");
    const before = section.getAllByRole("row").length;
    fireEvent.change(section.getByLabelText("Red team 1"), {
      target: { value: "7777" },
    });
    expect(
      section.getByRole("button", { name: "Reset to this match" }),
    ).toBeTruthy();
    expect(section.getAllByRole("row").length).toBeGreaterThan(before - 1);
    expect(section.getByRole("link", { name: "7777" })).toBeTruthy();
    fireEvent.click(
      section.getByRole("button", { name: "Reset to this match" }),
    );
    expect(
      (section.getByLabelText("Red team 1") as HTMLInputElement).value,
    ).toBe("1111");
  });

  it("asks for all six boxes and names teams short of entries", () => {
    view();
    const section = within(screen.getByRole("region", { name: "What if" }));
    expect(section.getByText(/Not enough scouted data/)).toBeTruthy();
    fireEvent.change(section.getByLabelText("Blue team 3"), {
      target: { value: "" },
    });
    expect(
      section.getByText(
        "Enter a team number in all six boxes to see a prediction.",
      ),
    ).toBeTruthy();
  });
});

describe("brief tab", () => {
  const written = {
    ...emptyBrief("2027test", "qm3"),
    robotPlans: { 1111: "Defend the ramp" },
    robotRoles: {
      1111: { auto: "Old auto text", start: "Left", teleop: "Defend" },
    },
    ready: true,
    authorDisplayName: "Lead B",
    updatedMs: 5,
  };
  const scouted = (team: number, n: number, values: Record<string, unknown>) =>
    Array.from({ length: n }, (_, i) =>
      entry(`${team}-${i}`, team, `2027test_qm${i + 1}`, values),
    );

  it("asks for our team number on a match we do not play", () => {
    myTeamStore.set(9999);
    view("/matches/2027test_qm3?tab=brief");
    expect(
      screen.getByText(/Briefs cover the matches our team plays/),
    ).toBeTruthy();
  });

  it("reads job, start and climb for all six robots with the Ready flag", () => {
    myTeamStore.set(1111);
    state.briefs = [written];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getAllByLabelText("Plan")).toHaveLength(6);
    expect(screen.getAllByText(/^Start: /)).toHaveLength(6);
    expect(screen.getAllByText(/^Climb: /)).toHaveLength(6);
    expect(screen.getByText("Written by Lead B")).toBeTruthy();
    const coach = screen
      .getByRole("heading", { name: "Match brief" })
      .closest("section") as HTMLElement;
    expect(within(coach).getByText("Ready")).toBeTruthy();
  });

  it("marks what the data recommends and shows the lead's change", () => {
    myTeamStore.set(1111);
    state.entries = scouted(1111, 3, { teleopFuelScored: 30 });
    state.briefs = [written];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getByText("Job: Defend")).toBeTruthy();
    expect(screen.getAllByText("Job: Flex")).toHaveLength(5);
    expect(screen.getAllByText("(recommended)").length).toBeGreaterThan(10);
  });

  it("says what the lead chose and what the data says for the climb", () => {
    myTeamStore.set(1111);
    state.entries = scouted(1111, 3, { teleopFuelScored: 30 });
    state.briefs = [{ ...written, robotRoles: { 1111: { endgame: "L2" } } }];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getByText("Climb: L2")).toBeTruthy();
    expect(
      screen.getByText(
        "Climb? You chose L2. Data says No climb: never tried to climb in 3 scouted matches",
      ),
    ).toBeTruthy();
  });

  it("does not show text typed in an earlier brief", () => {
    myTeamStore.set(1111);
    state.briefs = [written];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.queryByText(/Defend the ramp/)).toBeNull();
    expect(screen.queryByText(/Old auto text/)).toBeNull();
    expect(screen.queryByText(/Start: Left/)).toBeNull();
    expect(screen.queryByText(/^Notes:/)).toBeNull();
  });

  it("adds a Roles row from what scouts marked", () => {
    myTeamStore.set(1111);
    state.entries = [
      ...scouted(1111, 2, { teleopFuelScored: 10, tRdefense: true }),
      entry("x", 1111, "2027test_qm9", {
        teleopFuelScored: 10,
        tRdefense: false,
      }),
    ];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getByText("Roles: Defense 2/3")).toBeTruthy();
  });

  it("ends each robot with a scout summary and every comment word for word", () => {
    myTeamStore.set(1111);
    state.entries = [
      entry("a", 1111, "2027test_qm1", {
        teleopFuelScored: 10,
        comments: "Fast intake",
      }),
      entry("b", 1111, "2027test_qm2", {
        teleopFuelScored: 10,
        comments: "Died late",
      }),
    ];
    state.teamNotes = [
      {
        id: "2027test_1111",
        eventKey: "2027test",
        teamNumber: 1111,
        text: "Ask about their auto",
        authorDisplayName: "Lead A",
        updatedMs: Date.parse("2027-03-01T12:00:00Z"),
      },
    ];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getAllByText("What scouts said")).toHaveLength(6);
    const none = screen.getAllByRole("button", {
      name: "All scout comments (0)",
    });
    expect(none).toHaveLength(5);
    expect((none[0] as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(
      screen.getByRole("button", { name: "All scout comments (3)" }),
    );
    const sheet = screen.getByRole("dialog", {
      name: "1111: all scout comments",
    });
    expect(within(sheet).getByText("Fast intake")).toBeTruthy();
    expect(within(sheet).getByText("Died late")).toBeTruthy();
    expect(within(sheet).getByText("Ask about their auto")).toBeTruthy();
    fireEvent.keyDown(sheet, { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("shows each robot's average T-REx ratings for this event", () => {
    myTeamStore.set(1111);
    const rated = (
      id: string,
      trait: string,
      rating: number,
      eventKey = "",
    ) => ({
      id,
      trait,
      teamNumber: 1111,
      eventKey,
      report: "Text",
      rating,
      matchNumber: 0,
      scoutName: "Scout A",
      updatedAt: "2027-03-01T10:00:00.000Z",
    });
    state.trex = [
      rated("a", "defense", 5),
      rated("b", "defense", 4, "2027test"),
      rated("c", "defense", 1, "2026old"),
    ];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getByText("Defense: 4.5 from 2 ratings")).toBeTruthy();
  });

  it("shows no ratings line when no report is rated", () => {
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.queryByLabelText("T-REx ratings")).toBeNull();
  });

  it("shows a draft notice until the brief is ready", () => {
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=brief");
    expect(
      screen.getByText("Draft: the strategy lead has not marked this ready."),
    ).toBeTruthy();
  });

  it("lets a lead mark the brief ready", async () => {
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=brief");
    fireEvent.click(screen.getByRole("button", { name: "Mark ready" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const [prev, edit, author, label] = state.save.mock.calls[0] as unknown[];
    expect((prev as { id: string }).id).toBe("2027test_qm3");
    expect(edit).toEqual({ ready: true });
    expect(author).toEqual({ uid: "u1", displayName: "Scout A" });
    expect(label).toBe("Brief for Q3");
  });

  it("offers job, start and climb for the six robots, recommended first", () => {
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(
      screen.getAllByRole("group", { name: "Job this match" }),
    ).toHaveLength(6);
    expect(screen.getAllByLabelText("Start spot")).toHaveLength(6);
    expect(screen.getAllByLabelText("Climb this match")).toHaveLength(6);
    const flex = screen.getAllByRole("button", {
      name: "Flex (recommended)",
    });
    expect(flex).toHaveLength(6);
    expect(flex[0]?.getAttribute("aria-pressed")).toBe("true");
    const starts = screen.getAllByLabelText(
      "Start spot",
    )[0] as HTMLSelectElement;
    expect(
      [...starts.options].some((o) => o.text.endsWith("(recommended)")),
    ).toBe(true);
  });

  it("holds the choices until every scout entry has loaded", () => {
    state.entriesReady = false;
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=brief");
    const plan = screen.getByRole("group", { name: /^1111/ });
    const controls = [
      ...within(plan).getAllByRole("button"),
      ...within(plan).getAllByRole("combobox"),
    ];
    expect(controls.length).toBeGreaterThan(0);
    for (const control of controls) {
      expect((control as HTMLButtonElement).disabled).toBe(true);
    }
    expect(screen.getByText(/^Loading scout entries/)).toBeTruthy();
  });

  it("saves a changed job and keeps the other answers", async () => {
    myTeamStore.set(1111);
    state.briefs = [
      {
        ...written,
        robotRoles: { 1111: { auto: "Old auto text", start: "Left" } },
      },
    ];
    view("/matches/2027test_qm3?tab=brief");
    const group = screen.getAllByRole("group", { name: "Job this match" })[0];
    fireEvent.click(
      within(group as HTMLElement).getByRole("button", { name: "Defend" }),
    );
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const edit = state.save.mock.calls[0]?.[1] as {
      robotPlans?: unknown;
      robotRoles: Record<number, Record<string, string>>;
    };
    expect(edit.robotPlans).toBeUndefined();
    expect(edit.robotRoles[1111]).toEqual({
      auto: "Old auto text",
      start: "Left",
      teleop: "Defend",
    });
  });

  it("saves a changed start spot and climb", async () => {
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=brief");
    fireEvent.change(screen.getAllByLabelText("Start spot")[0] as HTMLElement, {
      target: { value: "Center Hub" },
    });
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const edit = state.save.mock.calls[0]?.[1] as {
      robotRoles: Record<number, Record<string, string>>;
    };
    expect(edit.robotRoles[1111]).toEqual({ start: "Center Hub" });
    fireEvent.change(
      screen.getAllByLabelText("Climb this match")[1] as HTMLElement,
      { target: { value: "L1" } },
    );
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(2));
    const second = state.save.mock.calls[1]?.[1] as {
      robotRoles: Record<number, Record<string, string>>;
    };
    expect(second.robotRoles[2222]).toEqual({ endgame: "L1" });
  });

  it("says what changed and clears the override on the recommended choice", async () => {
    myTeamStore.set(1111);
    state.briefs = [{ ...written, robotRoles: { 1111: { teleop: "Defend" } } }];
    view("/matches/2027test_qm3?tab=brief");
    expect(
      screen.getByText("Changed by you, recommended: Flex (not scouted yet)"),
    ).toBeTruthy();
    const group = screen.getAllByRole("group", { name: "Job this match" })[0];
    fireEvent.click(
      within(group as HTMLElement).getByRole("button", {
        name: "Flex (recommended)",
      }),
    );
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const edit = state.save.mock.calls[0]?.[1] as {
      robotRoles: Record<number, Record<string, string>>;
    };
    expect(edit.robotRoles[1111]).toEqual({});
  });

  it("shows the delivery state of the last save", () => {
    myTeamStore.set(1111);
    state.outbox = [
      {
        id: "i1",
        path: "matchBriefs/2027test_qm3",
        status: "in-database",
      },
    ];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getByText("In the database")).toBeTruthy();
  });

  it("is read only for a role that cannot edit", () => {
    myTeamStore.set(1111);
    setRoles(ready("scouter"));
    state.briefs = [written];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.queryByRole("button", { name: "Mark as draft" })).toBeNull();
    expect(screen.queryByRole("group", { name: "Job this match" })).toBeNull();
    expect(screen.getByText("Job: Defend")).toBeTruthy();
  });
});

describe("plan tab", () => {
  it("sits between Match and Brief and opens the board for this match", async () => {
    myTeamStore.set(1111);
    view("/matches/2027test_qm3?tab=plan");
    expect(
      await screen.findByText(
        "Board for 2027test_qm3, red 1111 2222 3333, we are red",
      ),
    ).toBeTruthy();
    const tabs = within(
      screen.getByRole("navigation", { name: "Match sections" }),
    ).getAllByRole("link");
    expect(tabs.map((t) => t.textContent)).toEqual(["Match", "Plan", "Brief"]);
    expect(tabs[1]?.getAttribute("aria-current")).toBe("page");
    expect(screen.queryByRole("table", { name: /Scouted stats/ })).toBeNull();
  });

  it("stays on the Plan tab when stepping to another match", () => {
    view("/matches/2027test_qm3?tab=plan");
    expect(
      screen.getByRole("link", { name: "Previous: Q2" }).getAttribute("href"),
    ).toBe("/matches/2027test_qm2?tab=plan");
  });

  it("is for leads only", () => {
    setRoles(ready("scouter"));
    view("/matches/2027test_qm3?tab=plan");
    expect(
      screen.getByText("The strategy board is for strategy leads."),
    ).toBeTruthy();
    expect(screen.queryByText(/^Board for/)).toBeNull();
  });
});

describe("a mentor", () => {
  const written = {
    ...emptyBrief("2027test", "qm3"),
    robotRoles: { 1111: { teleop: "Defend" } },
    ready: true,
    authorDisplayName: "Lead B",
    updatedMs: 5,
  };

  it("reads the brief in the coach view and sees no edit control", () => {
    myTeamStore.set(1111);
    setRoles(ready("mentor"));
    state.briefs = [written];
    view("/matches/2027test_qm3?tab=brief");
    expect(screen.getByText("Job: Defend")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Match brief" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Mark as draft" })).toBeNull();
    expect(screen.queryByRole("group", { name: "Job this match" })).toBeNull();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(screen.queryByRole("combobox")).toBeNull();
  });

  it("has no Plan tab and no board", () => {
    setRoles(ready("mentor"));
    view("/matches/2027test_qm3?tab=plan");
    const tabs = within(
      screen.getByRole("navigation", { name: "Match sections" }),
    ).getAllByRole("link");
    expect(tabs.map((t) => t.textContent)).toEqual(["Match", "Brief"]);
    expect(
      screen.getByText("The strategy board is for strategy leads."),
    ).toBeTruthy();
    expect(screen.queryByText(/^Board for/)).toBeNull();
  });

  it("opens on the brief", () => {
    myTeamStore.set(1111);
    setRoles(ready("mentor"));
    state.briefs = [written];
    view("/matches/2027test_qm3");
    expect(screen.getByRole("heading", { name: "Match brief" })).toBeTruthy();
  });

  it("reads the match tab of a played match with no report form", () => {
    setRoles(ready("mentor"));
    view("/matches/2027test_qm2?tab=match");
    expect(screen.getByRole("table", { name: /Scouted stats/ })).toBeTruthy();
    expect(
      screen.getByRole("heading", { name: "Post match report" }),
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Save report" })).toBeNull();
    const whatIf = screen.getByRole("region", { name: "What if" });
    for (const box of screen.getAllByRole("textbox")) {
      if (whatIf.contains(box)) continue;
      expect((box as HTMLTextAreaElement).readOnly).toBe(true);
    }
  });
});

describe("why this prediction and why this result", () => {
  const red = [1111, 2222, 3333];
  const blue = [4444, 5555, 6666];
  const earlier = [
    ...red.flatMap((t) =>
      [1, 2, 3].map((n) =>
        entry(`${t}-${n}`, t, `2027test_qm${n}`, {
          autoFuelScored: 3 + n,
          teleopFuelScored: 9 + n,
        }),
      ),
    ),
    ...blue.flatMap((t) =>
      [1, 2, 3].map((n) =>
        entry(`${t}-${n}`, t, `2027test_qm${n}`, {
          autoFuelScored: 1 + n,
          teleopFuelScored: 3 + n,
        }),
      ),
    ),
  ];
  const playedQm4 = [
    entry("a", 1111, "2027test_qm4", {
      autoFuelScored: 6,
      teleopFuelScored: 14,
      comments: "Jammed twice",
    }),
    entry("b", 2222, "2027test_qm4", {
      autoFuelScored: 5,
      teleopFuelScored: 11,
    }),
    entry("c", 3333, "2027test_qm4", {
      autoFuelScored: 4,
      teleopFuelScored: 10,
    }),
  ];
  const at = (key: string) => `/matches/2027test_${key}`;

  it("explains an upcoming match from all the scouting", () => {
    state.matches = [qm(4, false)];
    state.entries = earlier;
    view(at("qm4"));
    const section = screen
      .getByRole("heading", { name: "Why this prediction" })
      .closest("section") as HTMLElement;
    expect(
      within(section).getByText(/^Scouting expects Red to score 48 fuel/),
    ).toBeTruthy();
    expect(
      within(section).getByText("Made from all scouting so far."),
    ).toBeTruthy();
    expect(
      screen.queryByRole("heading", { name: "Why this result" }),
    ).toBeNull();
  });

  it("predicts a played match from earlier matches, not its own scouting", () => {
    state.matches = [qm(4, true)];
    state.entries = [
      ...earlier,
      entry("late", 1111, "2027test_qm4", {
        autoFuelScored: 90,
        teleopFuelScored: 900,
      }),
    ];
    view(at("qm4"));
    const table = screen.getByRole("table", {
      name: "Predicted score per alliance",
    });
    const scouted = within(table).getByRole("row", { name: /From scouting/ });
    expect(within(scouted).getByText("48.0")).toBeTruthy();
    expect(within(scouted).getByText("24.0")).toBeTruthy();
    expect(within(scouted).queryByText(/^[1-9]\d\d/)).toBeNull();
    expect(screen.getByText(/^Made as it stood before the match/)).toBeTruthy();
  });

  it("explains the result with the official breakdown and the miss split", () => {
    state.matches = [qm(4, true)];
    state.entries = [...earlier, ...playedQm4];
    state.official = [
      {
        matchKey: "2027test_qm4",
        alliance: "red",
        teams: red,
        count: 30,
        climbPoints: 6,
        foulPoints: 4,
        foulCount: 1,
        video: "abc123",
      },
    ];
    view(at("qm4"));
    const section = screen
      .getByRole("heading", { name: "Why this result" })
      .closest("section") as HTMLElement;
    const why = within(section);
    expect(
      why.getByText("Red won by 5, as predicted (99% from our scouting)."),
    ).toBeTruthy();
    expect(
      why.getByText(/^Official total 40 = fuel 30 \+ climb 6 \+ fouls 4/),
    ).toBeTruthy();
    expect(why.getByText(/robots against their forecasts \+2/)).toBeTruthy();
    expect(why.getByText(/Jammed twice/)).toBeTruthy();
    expect(
      why
        .getByRole("link", { name: "Watch the match video" })
        .getAttribute("href"),
    ).toBe("https://www.youtube.com/watch?v=abc123");
  });

  it("says so when the official breakdown has not loaded", () => {
    state.matches = [qm(4, true)];
    state.entries = [...earlier, ...playedQm4];
    view(at("qm4"));
    expect(
      screen.getByText(/The official score breakdown has not loaded/),
    ).toBeTruthy();
  });

  it("shows no result explanation for an upcoming match", () => {
    state.matches = [qm(4, false)];
    view(at("qm4"));
    expect(
      screen.queryByRole("heading", { name: "Why this result" }),
    ).toBeNull();
  });
});
