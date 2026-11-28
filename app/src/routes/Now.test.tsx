// @vitest-environment jsdom
import { cleanup, render, screen, within } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { emptyBrief } from "../match/brief";
import { myTeamStore } from "../now/myTeam";
import { routes } from "../routes";
import type { ScheduledMatch } from "../scout/schedule";

const state = vi.hoisted(() => ({
  entries: { items: [], ready: true, failed: false } as {
    items: unknown[];
    ready: boolean;
    failed: boolean;
  },
  briefs: { items: [], ready: true, failed: false } as {
    items: unknown[];
    ready: boolean;
    failed: boolean;
  },
  outbox: [] as unknown[],
  forecasts: { status: "ready", data: null } as Record<string, unknown>,
}));

vi.mock("virtual:pwa-register/react", () => ({
  useRegisterSW: () => ({
    needRefresh: [false, () => undefined],
    offlineReady: [false, () => undefined],
    updateServiceWorker: () => Promise.resolve(),
  }),
}));
vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: "signed-out",
    uid: null,
    displayName: null,
    email: null,
    error: null,
    signIn: () => Promise.resolve(),
    signOut: () => Promise.resolve(),
  }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/outbox", () => ({
  dismissFinished: () => undefined,
  dismissItem: () => undefined,
  enqueueProofEntry: () => Promise.resolve("id"),
  deleteProofEntries: () => Promise.resolve(0),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../data/entries", () => ({
  useEventEntries: () => state.entries,
}));
vi.mock("../data/useCollections", async () => {
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const { parseConfig } = await import("../scout/config");
  return {
    usePitEntries: () => ({ items: [], ready: true, failed: false }),
    usePrescoutEntries: () => ({ items: [], ready: true, failed: false }),
    useTrexReports: () => ({ items: [], ready: true, failed: false }),
    useFormConfig: () => parseConfig(pit.default),
  };
});
vi.mock("../match/useBriefs", () => ({ useBriefs: () => state.briefs }));
vi.mock("../match/useOutside", () => ({
  useEpa: () => ({ status: "ready", data: null }),
  useForecasts: () => state.forecasts,
}));
vi.mock("../scout/remote", () => ({
  watchScoutConfig: () => () => undefined,
  watchActiveEvent: () => () => undefined,
  watchEventEntries: () => () => undefined,
  fetchTbaKey: () => Promise.resolve(null),
}));

const match = (
  n: number,
  red: number[],
  blue: number[],
  played = false,
  level = "qm",
): ScheduledMatch => ({
  key: level === "qm" ? `2027test_qm${n}` : `2027test_${level}${n}m1`,
  compLevel: level,
  matchNumber: level === "qm" ? n : 1,
  red,
  blue,
  time: 1_803_055_320 + n * 420,
  redScore: played ? 40 : -1,
  blueScore: played ? 30 : -1,
});

const schedule = [
  match(1, [1111, 2222, 3333], [4444, 5555, 6666], true),
  match(2, [7001, 7002, 7003], [7004, 7005, 7006]),
  match(3, [4444, 5555, 6666], [1111, 2222, 3333]),
  match(4, [1111, 8002, 8003], [8004, 8005, 8006]),
];

function setup(
  matches: ScheduledMatch[] = schedule,
  team: number | null = 1111,
) {
  localStorage.setItem("ss.event.key", JSON.stringify("2027test"));
  localStorage.setItem(
    "ss.schedule.2027test",
    JSON.stringify({ fetchedAt: "2027-02-19T16:00:00.000Z", matches }),
  );
  myTeamStore.set(team);
  window.innerWidth = 1280;
  render(
    <RouterProvider
      router={createMemoryRouter(routes, { initialEntries: ["/"] })}
    />,
  );
}

beforeEach(() => {
  localStorage.setItem("ss.tour.seen", "1");
});
afterEach(() => {
  cleanup();
  state.entries = { items: [], ready: true, failed: false };
  state.briefs = { items: [], ready: true, failed: false };
  state.outbox = [];
  state.forecasts = { status: "ready", data: null };
  localStorage.clear();
  myTeamStore.set(null);
  setRoles(ready("strategy"));
  vi.restoreAllMocks();
});

const headings = () =>
  screen.getAllByRole("heading", { level: 2 }).map((h) => h.textContent);

describe("Now without a schedule or team", () => {
  it("asks for an event when none is set", () => {
    window.innerWidth = 1280;
    render(
      <RouterProvider
        router={createMemoryRouter(routes, { initialEntries: ["/"] })}
      />,
    );
    expect(screen.getByText(/No event is set/)).toBeTruthy();
    expect(screen.getByRole("link", { name: "Open Settings" })).toBeTruthy();
  });

  it("uses team 3847 when no team number is set", () => {
    setup(schedule, null);
    expect(
      screen.getByText("Team 3847 is not on the schedule for 2027test."),
    ).toBeTruthy();
  });

  it("says when the schedule is not out", () => {
    setup([]);
    expect(
      screen.getByText("The match schedule for 2027test is not out yet."),
    ).toBeTruthy();
  });

  it("says when the team is not on the schedule", () => {
    setup(schedule, 9999);
    expect(
      screen.getByText("Team 9999 is not on the schedule for 2027test."),
    ).toBeTruthy();
  });
});

describe("Now for a lead", () => {
  it("leads with our next match, then rank and later matches", () => {
    setup();
    expect(headings()).toEqual([
      "Our next match",
      "Rank and record",
      "Our last match",
      "Scouting coverage",
      "Our later matches",
    ]);
    expect(screen.getByText("Q3")).toBeTruthy();
    expect(screen.getByText("1 match away")).toBeTruthy();
    const next = screen.getByRole("region", { name: "Our next match" });
    expect(within(next).getByText(/^Scheduled /)).toBeTruthy();
    expect(within(next).getByText("us")).toBeTruthy();
  });

  it("links team numbers and the Prep action", () => {
    setup();
    const next = screen.getByRole("region", { name: "Our next match" });
    expect(
      within(next).getByRole("link", { name: "4444" }).getAttribute("href"),
    ).toBe("/teams/4444");
    expect(
      within(next).getByRole("link", { name: "Prep" }).getAttribute("href"),
    ).toBe("/matches/2027test_qm3");
  });

  it("lists the remaining matches with partners", () => {
    setup();
    const later = screen.getByRole("region", { name: "Our later matches" });
    expect(within(later).getByRole("link", { name: "Q4" })).toBeTruthy();
    expect(within(later).getByRole("link", { name: "8002" })).toBeTruthy();
  });

  it("says rank is not posted yet rather than showing a blank", () => {
    setup();
    expect(screen.getByText(/has no ranking for this team yet/)).toBeTruthy();
    expect(screen.getByText("Played 1 of 3 scheduled matches.")).toBeTruthy();
  });

  it("says when all our matches are played", () => {
    setup([match(1, [1111, 2222, 3333], [4444, 5555, 6666], true)]);
    expect(
      screen.getByText(/All 1 of Team 1111's scheduled matches are played/),
    ).toBeTruthy();
  });

  it("says when the schedule is finished", () => {
    setup([
      match(1, [1111, 2222, 3333], [4444, 5555, 6666], true),
      match(1, [1111, 2222, 3333], [4444, 5555, 6666], true, "f"),
    ]);
    expect(
      screen.getByText(
        "No matches are left on the schedule. Team 1111 played 2.",
      ),
    ).toBeTruthy();
  });

  it("says it is offline and shows the cached schedule", () => {
    vi.spyOn(navigator, "onLine", "get").mockReturnValue(false);
    setup();
    expect(
      screen.getByText(/Offline\. Showing the schedule from/),
    ).toBeTruthy();
    expect(screen.getByText("Q3")).toBeTruthy();
  });
});

const entryFor = (team: number, key = "2027test_qm1") => ({
  id: `${key}-${team}`,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: {},
});

describe("Now for a lead: prediction and brief", () => {
  it("shows the predicted score with its sources inside the next match", () => {
    setup();
    const next = screen.getByRole("region", { name: "Our next match" });
    expect(
      within(next).getByRole("heading", { name: "Predicted score" }),
    ).toBeTruthy();
    expect(
      within(next).getByRole("table", { name: "Predicted score per alliance" }),
    ).toBeTruthy();
    expect(within(next).getByText(/Statbotics has no EPA/)).toBeTruthy();
    expect(
      within(next).getByText(/no forecast for this match yet/),
    ).toBeTruthy();
  });

  it("shows the forecast for the next match", () => {
    state.forecasts = {
      status: "ready",
      data: { "2027test_qm3": { redScore: 31.5, blueScore: 44, redWin: 0.3 } },
    };
    setup();
    const next = screen.getByRole("region", { name: "Our next match" });
    expect(within(next).getByText("31.5")).toBeTruthy();
    expect(within(next).getByText("30%")).toBeTruthy();
  });

  it("says there is no brief and links to the Brief tab", () => {
    setup();
    const next = screen.getByRole("region", { name: "Our next match" });
    expect(within(next).getByText("No brief yet")).toBeTruthy();
    expect(
      within(next).getByRole("link", { name: "Brief" }).getAttribute("href"),
    ).toBe("/matches/2027test_qm3?tab=brief");
  });

  it("says when the brief is ready", () => {
    state.briefs = {
      items: [
        {
          ...emptyBrief("2027test", "qm3"),
          keyPoints: "Defend the left side",
          ready: true,
        },
      ],
      ready: true,
      failed: false,
    };
    setup();
    expect(screen.getByText("Ready")).toBeTruthy();
  });

  it("does not claim a brief status when briefs could not be read", () => {
    state.briefs = { items: [], ready: true, failed: true };
    setup();
    expect(screen.getByText("Briefs could not be read.")).toBeTruthy();
    expect(screen.queryByText("No brief yet")).toBeNull();
  });
});

describe("Now for a lead: last match and coverage", () => {
  it("shows our last result above the later matches", () => {
    setup();
    const last = screen.getByRole("region", { name: "Our last match" });
    expect(within(last).getByText("Won 40 to 30")).toBeTruthy();
    expect(within(last).getByRole("link", { name: "Q1" })).toBeTruthy();
  });

  it("lists robots nobody scouted in the recent played matches", () => {
    state.entries = {
      items: [entryFor(1111), entryFor(2222)],
      ready: true,
      failed: false,
    };
    setup();
    const region = screen.getByRole("region", { name: "Scouting coverage" });
    expect(
      within(region).getByText(/4 robots have no scout entry/),
    ).toBeTruthy();
    expect(
      within(region).getByRole("link", { name: "Q1" }).getAttribute("href"),
    ).toBe("/matches/2027test_qm1");
    expect(within(region).getByRole("link", { name: "3333" })).toBeTruthy();
    expect(within(region).queryByRole("link", { name: "1111" })).toBeNull();
  });

  it("says when every robot was scouted", () => {
    state.entries = {
      items: [1111, 2222, 3333, 4444, 5555, 6666].map((t) => entryFor(t)),
      ready: true,
      failed: false,
    };
    setup();
    expect(
      screen.getByText("Every robot in Q1 to Q1 has a scout entry."),
    ).toBeTruthy();
  });

  it("does not report gaps while entries are unread or unreadable", () => {
    state.entries = { items: [], ready: false, failed: false };
    setup();
    expect(screen.getByText("Reading scout entries.")).toBeTruthy();
    cleanup();
    state.entries = { items: [], ready: true, failed: true };
    setup();
    expect(
      screen.getByText(
        "Could not read the scout entries, so coverage is unknown.",
      ),
    ).toBeTruthy();
    expect(screen.queryByText(/have no scout entry/)).toBeNull();
  });

  it("flags scout entries still on this device", () => {
    state.entries = { items: [], ready: true, failed: false };
    state.outbox = [
      { id: "1", path: "scoutEntries/a", status: "on-device" },
      { id: "2", path: "scoutEntries/b", status: "sending" },
      { id: "3", path: "scoutEntries/c", status: "refused" },
      { id: "4", path: "scoutEntries/d", status: "in-database" },
      { id: "5", path: "matchBriefs/x", status: "on-device" },
    ];
    setup();
    expect(
      screen.getByText(/2 scout entries are on this device and not in the/),
    ).toBeTruthy();
    expect(screen.getByText(/refused 1 scout entry/)).toBeTruthy();
    const region = screen.getByRole("region", { name: "Scouting coverage" });
    expect(
      within(region)
        .getByRole("link", { name: "Open Scout" })
        .getAttribute("href"),
    ).toBe("/scout");
  });
});

describe("Now for a scouter", () => {
  it("keeps the scout view free of the lead sections", () => {
    setRoles(ready("scouter"));
    setup();
    expect(headings()).not.toContain("Scouting coverage");
    expect(headings()).not.toContain("Our last match");
    expect(screen.queryByText("Predicted score")).toBeNull();
    expect(screen.queryByRole("link", { name: "Brief" })).toBeNull();
  });

  it("leads with their scouting, and shows team numbers as plain text", () => {
    setRoles(ready("scouter"));
    setup();
    expect(headings()[0]).toBe("Your scouting");
    expect(
      screen.getByText("No scouting shifts are set up for this event yet."),
    ).toBeTruthy();
    expect(
      screen.getByRole("link", { name: "Start" }).getAttribute("href"),
    ).toBe("/scout");
    expect(
      screen
        .getByRole("link", { name: "Scouting shifts" })
        .getAttribute("href"),
    ).toBe("/scout/shifts");
    expect(screen.getByText("4444")).toBeTruthy();
    expect(screen.queryByRole("link", { name: "4444" })).toBeNull();
    expect(screen.queryByRole("link", { name: "Prep" })).toBeNull();
    expect(screen.queryByRole("link", { name: "Q4" })).toBeNull();
  });
});

describe("Now for a mentor", () => {
  function open() {
    localStorage.setItem("ss.event.key", JSON.stringify("2027test"));
    localStorage.setItem(
      "ss.schedule.2027test",
      JSON.stringify({
        fetchedAt: "2027-02-19T16:00:00.000Z",
        matches: schedule,
      }),
    );
    myTeamStore.set(1111);
    window.innerWidth = 1280;
    const router = createMemoryRouter(routes, { initialEntries: ["/"] });
    render(<RouterProvider router={router} />);
    return router;
  }

  it("opens on the next match's brief", () => {
    setRoles(ready("mentor"));
    const router = open();
    expect(router.state.location.pathname).toBe("/matches/2027test_qm3");
    expect(router.state.location.search).toBe("?tab=brief");
  });

  it("stays on Now when the mentor also scouts", () => {
    setRoles(ready("mentor", "scouter"));
    const router = open();
    expect(router.state.location.pathname).toBe("/");
    expect(headings()[0]).toBe("Your scouting");
  });

  it("stays on Now with no shift or scout link when there is no next match", () => {
    setRoles(ready("mentor"));
    localStorage.setItem("ss.event.key", JSON.stringify("2027test"));
    localStorage.setItem(
      "ss.schedule.2027test",
      JSON.stringify({
        fetchedAt: "2027-02-19T16:00:00.000Z",
        matches: [match(1, [1111, 2222, 3333], [4444, 5555, 6666], true)],
      }),
    );
    myTeamStore.set(1111);
    window.innerWidth = 1280;
    const router = createMemoryRouter(routes, { initialEntries: ["/"] });
    render(<RouterProvider router={router} />);
    expect(router.state.location.pathname).toBe("/");
    expect(screen.getByText(/All 1 of Team 1111's scheduled/)).toBeTruthy();
    expect(screen.queryByRole("link", { name: "Scouting shifts" })).toBeNull();
    expect(screen.queryByRole("link", { name: "Start" })).toBeNull();
  });
});
