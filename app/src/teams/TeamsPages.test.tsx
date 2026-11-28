// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { ready, setRoles } from "../auth/rolesMock";
import type { EventEntry } from "../data/parse";
import { forgetDrafts, setTaken } from "../picks/draftStore";
import { parseConfig } from "../scout/config";
import { Analysis } from "./AnalysisPage";
import { Compare } from "./ComparePage";
import { Teams } from "./TeamsPage";

const config = parseConfig(bundled);
const numbers = [1001, 1002, 1003, 1004, 1005, 1006];

const state = vi.hoisted(() => ({
  entries: [] as unknown[],
  pit: [] as unknown[],
  epa: null as Record<number, number> | null,
  epaStatus: "ready",
  entriesFailed: false,
  entriesReady: true,
  pitReady: true,
  tbaStatus: "ready",
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: "signed-in", uid: "u1" }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({ config, eventKey: "2027test", schedule: [] }),
}));
vi.mock("../data/useCorrections", () => ({
  useCorrections: () => ({ items: [], ready: true, failed: false }),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({
    items: state.entries,
    ready: state.entriesReady,
    failed: state.entriesFailed,
  }),
}));
vi.mock("../data/useCollections", async () => {
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const { parseConfig: parse } = await import("../scout/config");
  return {
    usePitEntries: () => ({
      items: state.pit,
      ready: state.pitReady,
      failed: false,
    }),
    useFormConfig: () => parse(pit.default),
  };
});
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027test",
    status: state.tbaStatus,
    fetchedAt: "2027-03-01T12:00:00.000Z",
    teams: numbers.map((number) => ({ number, nickname: `Bots ${number}` })),
    rankings: numbers.map((team, i) => ({
      team,
      rank: numbers.length - i,
      wins: 1,
      losses: 0,
      ties: 0,
    })),
    matches: [],
  }),
}));
vi.mock("../match/useOutside", () => ({
  useEpa: () => ({ status: state.epaStatus, data: state.epa }),
}));

function entry(team: number, match: number, total: number): EventEntry {
  return {
    id: `${team}-${match}`,
    tbaMatchKey: `2027test_qm${match}`,
    teamNumber: team,
    alliance: "Red",
    scoutName: "Scout A",
    updatedAt: "2027-03-01T12:00:00.000Z",
    fieldValues: { autoFuelScored: 0, teleopFuelScored: total },
  };
}

const scouted = () => [
  ...[10, 20, 30].map((t, i) => entry(1001, i + 1, t)),
  ...[30, 30, 30].map((t, i) => entry(1002, i + 1, t)),
  ...[5, 10, 6].map((t, i) => entry(1003, i + 1, t)),
];

function LocationProbe() {
  const { pathname, search } = useLocation();
  return <p data-testid="where">{pathname + search}</p>;
}

function view(path = "/teams", width = 1280) {
  window.innerWidth = width;
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/teams" element={<Teams />} />
        <Route path="/teams/compare" element={<Compare />} />
        <Route path="/teams/analysis" element={<Analysis />} />
      </Routes>
      <LocationProbe />
    </MemoryRouter>,
  );
}

const order = () =>
  Array.from(
    document.querySelectorAll("tbody a.team-ref, .teams-item a.team-ref"),
  ).map((a) => a.textContent);

beforeEach(() => {
  localStorage.clear();
  forgetDrafts();
  setRoles(ready("strategy"));
  state.entries = scouted();
  state.pit = [];
  state.epa = { 1001: 10, 1002: 60, 1003: 40, 1004: 30, 1005: 20 };
  state.epaStatus = "ready";
  state.entriesFailed = false;
  state.entriesReady = true;
  state.pitReady = true;
  state.tbaStatus = "ready";
});
afterEach(cleanup);

describe("pick meeting filters", () => {
  const defended = () => [
    ...[1, 2].map((m) => ({
      ...entry(1001, m, 10),
      id: `d1001-${m}`,
      fieldValues: {
        teleopFuelScored: 10,
        tRdefense: true,
        eHigh: "Successful",
      },
    })),
    ...[1, 2].map((m) => ({
      ...entry(1002, m, 10),
      id: `d1002-${m}`,
      fieldValues: { teleopFuelScored: 10, eHigh: "Successful" },
    })),
  ];

  it("shows a live count per filter and narrows with AND", () => {
    state.entries = defended();
    view();
    fireEvent.click(screen.getByRole("button", { name: "Filters" }));
    expect(screen.getByRole("button", { name: "Climbs L3 (2)" })).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "Plays defense (1)" }),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Climbs L3 (2)" }));
    expect(screen.getByText("2 of 6 teams")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Plays defense (1)" }));
    expect(screen.getByText("1 of 6 teams")).toBeTruthy();
    expect(screen.getByTestId("where").textContent).toBe(
      "/teams?f=l3%2Cdefense",
    );
    expect(order()).toEqual(["1001"]);
  });

  it("restores filters from the address and clears them", () => {
    state.entries = defended();
    view("/teams?f=defense");
    expect(screen.getByText("1 of 6 teams")).toBeTruthy();
    expect(order()).toEqual(["1001"]);
    fireEvent.click(screen.getByRole("button", { name: "Clear filters" }));
    expect(order()).toHaveLength(6);
    expect(screen.getByTestId("where").textContent).toBe("/teams");
  });

  it("says when no team passes", () => {
    state.entries = defended();
    view("/teams?f=autoclimb");
    expect(
      screen.getByText(/No team passes every selected filter/),
    ).toBeTruthy();
  });

  it("offers no turret filter and groups the ten by question", () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: "Filters" }));
    expect(screen.queryByText(/turret/i)).toBeNull();
    expect(screen.getByRole("group", { name: "Can they do it?" })).toBeTruthy();
    expect(screen.getByRole("group", { name: "What job?" })).toBeTruthy();
    expect(
      screen.getByRole("group", { name: "Can we trust them?" }),
    ).toBeTruthy();
    expect(document.querySelectorAll(".teams-filter-chips .chip")).toHaveLength(
      10,
    );
  });
});

describe("team list table", () => {
  it("does not claim teams are unscouted before entries arrive", () => {
    state.entries = [];
    state.entriesReady = false;
    view("/teams", 390);
    expect(screen.getByText(/Loading scouted stats/)).toBeTruthy();
    expect(screen.queryByText(/0 scouted|Not scouted/)).toBeNull();
  });

  it("waits for pit entries before showing an empty pit comparison", () => {
    state.pitReady = false;
    view("/teams/compare?t=1001,1002", 390);
    expect(screen.getByText("Loading pit entries.")).toBeTruthy();
    expect(screen.queryByText(/No pit entry yet/)).toBeNull();
  });
  it("orders by EPA, then TBA rank for a team without one", () => {
    view();
    expect(order()).toEqual(["1002", "1003", "1004", "1005", "1001", "1006"]);
    expect(screen.getByText("6 teams", { exact: false })).toBeTruthy();
  });

  it("sorts by a column heading and reverses on a second press", () => {
    view();
    const head = screen.getByRole("columnheader", { name: "Score" });
    fireEvent.click(within(head).getByRole("button"));
    expect(order().slice(0, 3)).toEqual(["1002", "1001", "1003"]);
    expect(head.getAttribute("aria-sort")).toBe("descending");
    fireEvent.click(within(head).getByRole("button"));
    expect(order().slice(0, 3)).toEqual(["1003", "1001", "1002"]);
    expect(head.getAttribute("aria-sort")).toBe("ascending");
  });

  it("searches by number and by nickname", () => {
    view();
    const box = screen.getByLabelText("Search by number or nickname");
    fireEvent.change(box, { target: { value: "1003" } });
    expect(order()).toEqual(["1003"]);
    expect(screen.getByText("1 of 6 teams.")).toBeTruthy();
    fireEvent.change(box, { target: { value: "bots 1005" } });
    expect(order()).toEqual(["1005"]);
    fireEvent.change(box, { target: { value: "nobody" } });
    expect(screen.getByText('No team matches "nobody".')).toBeTruthy();
  });

  it("tints a column by place, and the top cell is the strongest", () => {
    view();
    const first = document.querySelector("tbody tr");
    const epa = first?.querySelectorAll("td")[0];
    expect(epa?.textContent).toBe("60");
    expect(epa?.getAttribute("data-heat")).toBe("4");
  });

  it("draws a sparkline with a text alternative from three matches", () => {
    view();
    expect(
      screen.getByRole("img", {
        name: "Match totals: Q1 10, Q2 20, Q3 30",
      }),
    ).toBeTruthy();
  });

  it("greys a picked team and says who took it", () => {
    setTaken("2027test", { 1002: "Picked by alliance 2" });
    view();
    const row = document.querySelector("tbody tr");
    expect(row?.getAttribute("data-picked")).toBe("true");
    expect(
      within(row as HTMLElement).getByText("Picked by alliance 2"),
    ).toBeTruthy();
    expect(
      row?.querySelectorAll("td")[0]?.getAttribute("data-heat"),
    ).toBeNull();
  });

  it("says teams are ordered by TBA rank when there is no EPA", () => {
    state.epa = null;
    view();
    expect(
      screen.getByText(/Statbotics has no EPA for this event/),
    ).toBeTruthy();
    expect(order()[0]).toBe("1006");
  });

  it("says when Statbotics could not be reached", () => {
    state.epa = null;
    state.epaStatus = "failed";
    view();
    expect(screen.getByText(/Statbotics could not be reached/)).toBeTruthy();
  });

  it("warns when the scout entries could not be read", () => {
    state.entriesFailed = true;
    view();
    expect(
      screen.getByText(/Could not read the latest scout entries/),
    ).toBeTruthy();
  });
});

describe("team list on a phone", () => {
  it("shows a list with a sort menu instead of the table", () => {
    view("/teams", 390);
    expect(document.querySelector("table")).toBeNull();
    expect(order()[0]).toBe("1002");
    fireEvent.change(screen.getByLabelText("Sort by"), {
      target: { value: "total" },
    });
    expect(order().slice(0, 3)).toEqual(["1002", "1001", "1003"]);
    fireEvent.click(screen.getByRole("button", { name: "Reverse" }));
    expect(order().slice(0, 3)).toEqual(["1003", "1001", "1002"]);
  });

  it("greys a picked team in the list", () => {
    setTaken("2027test", { 1003: "Captain of alliance 1" });
    view("/teams", 390);
    expect(screen.getByText("Captain of alliance 1")).toBeTruthy();
    expect(
      document.querySelector('.teams-item[data-picked="true"]'),
    ).toBeTruthy();
  });
});

describe("choosing teams to compare", () => {
  it("links to Compare once two are ticked", () => {
    view();
    expect(
      (screen.getByRole("button", { name: "Compare" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    fireEvent.click(screen.getByLabelText("Compare 1001"));
    fireEvent.click(screen.getByLabelText("Compare 1003"));
    const link = screen.getByRole("link", { name: "Compare" });
    expect(link.getAttribute("href")).toBe("/teams/compare?t=1001,1003");
    fireEvent.click(link);
    expect(screen.getByRole("heading", { name: "Compare teams" })).toBeTruthy();
    expect(screen.getByTestId("where").textContent).toBe(
      "/teams/compare?t=1001,1003",
    );
  });

  it("stops at four", () => {
    view();
    for (const team of [1001, 1002, 1003, 1004]) {
      fireEvent.click(screen.getByLabelText(`Compare ${team}`));
    }
    expect(
      (screen.getByLabelText("Compare 1005") as HTMLInputElement).disabled,
    ).toBe(true);
    expect(screen.getByText(/Compare takes up to 4 teams/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Clear ticks" }));
    expect(
      (screen.getByLabelText("Compare 1005") as HTMLInputElement).disabled,
    ).toBe(false);
  });
});

describe("compare", () => {
  it("shows the teams side by side with the best value marked", () => {
    view("/teams/compare?t=1001,1002");
    const table = screen.getByRole("table");
    const head = table.querySelector("thead") as HTMLElement;
    expect(within(head).getAllByRole("columnheader")).toHaveLength(3);
    const epa = within(table).getByRole("row", { name: /EPA/ });
    const cells = within(epa).getAllByRole("cell");
    expect(cells.map((c) => c.textContent)).toEqual(["10", "60 (best)"]);
    expect(cells[1]?.getAttribute("data-best")).toBe("true");
    expect(within(table).getAllByRole("img").length).toBe(2);
  });

  it("lists pit facts and names the team with no pit entry", () => {
    state.pit = [
      {
        id: "p1",
        teamNumber: 1001,
        eventKey: "",
        fieldValues: { trenchFit: true, drivetrainType: "swerve" },
        authorUid: "u1",
        scoutName: "Scout A",
        updatedAt: "2027-03-01T10:00:00.000Z",
        photoKeys: [],
      },
    ];
    view("/teams/compare?t=1001,1002");
    const table = screen.getByRole("table");
    const trench = within(table).getByRole("row", {
      name: /Fits under trench/,
    });
    expect(
      within(trench)
        .getAllByRole("cell")
        .map((c) => c.textContent),
    ).toEqual(["Yes", "-no data"]);
    expect(screen.getByText("No pit entry yet for 1002.")).toBeTruthy();
  });

  it("adds a team by number and removes one, keeping the address current", () => {
    view("/teams/compare?t=1001,1002");
    fireEvent.change(screen.getByLabelText("Add a team by number"), {
      target: { value: "1003" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Add" }));
    expect(screen.getByTestId("where").textContent).toBe(
      "/teams/compare?t=1001%2C1002%2C1003",
    );
    fireEvent.click(screen.getByRole("button", { name: "Remove 1001" }));
    expect(screen.getByTestId("where").textContent).toBe(
      "/teams/compare?t=1002%2C1003",
    );
  });

  it("refuses a team that is not at the event, a repeat and a bad number", () => {
    view("/teams/compare?t=1001,1002");
    const box = screen.getByLabelText("Add a team by number");
    const add = screen.getByRole("button", { name: "Add" });
    fireEvent.change(box, { target: { value: "9999" } });
    fireEvent.click(add);
    expect(screen.getByRole("alert").textContent).toMatch(/not at this event/);
    fireEvent.change(box, { target: { value: "1001" } });
    fireEvent.click(add);
    expect(screen.getByRole("alert").textContent).toMatch(/already here/);
    fireEvent.change(box, { target: { value: "x" } });
    fireEvent.click(add);
    expect(screen.getByRole("alert").textContent).toMatch(
      /Enter a team number/,
    );
  });

  it("closes the picker at four teams", () => {
    view("/teams/compare?t=1001,1002,1003,1004");
    expect(
      (screen.getByLabelText("Add a team by number") as HTMLInputElement)
        .disabled,
    ).toBe(true);
  });

  it("asks for teams when none are chosen and for one more when only one is", () => {
    view("/teams/compare");
    expect(screen.getByText(/Add 2 to 4 teams above/)).toBeTruthy();
    cleanup();
    view("/teams/compare?t=1001");
    expect(screen.getByText("Add one more team to compare.")).toBeTruthy();
  });

  it("stacks each stat as a list on a phone", () => {
    view("/teams/compare?t=1001,1002", 390);
    expect(document.querySelector("table")).toBeNull();
    const epa = screen.getByRole("heading", { name: "EPA" }).parentElement;
    expect(within(epa as HTMLElement).getAllByRole("listitem")).toHaveLength(2);
  });
});

describe("event analysis", () => {
  it("opens from teams and offers spread sizes", () => {
    view("/teams/analysis");
    expect(
      screen.getByRole("heading", { name: "Event analysis" }),
    ).toBeTruthy();
    expect(
      screen.getByRole("heading", { name: "Match score spread" }),
    ).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Teams shown"), {
      target: { value: "16" },
    });
    expect(
      (screen.getByLabelText("Teams shown") as HTMLSelectElement).value,
    ).toBe("16");
  });
});
