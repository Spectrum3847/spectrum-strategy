// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import type { AllianceFuel } from "../data/tbaBreakdown";
import type { MappingDoc } from "./mapping";

const state = vi.hoisted(() => ({
  eventKey: "2027test",
  entries: [] as unknown[],
  entriesReady: true,
  official: {
    status: "ready",
    alliances: [] as unknown[],
    fetchedAt: null as string | null,
    problem: null as string | null,
    refresh: () => undefined,
  },
  mapping: { status: "ready", mapping: null } as {
    status: string;
    mapping: unknown;
  },
  saved: [] as unknown[],
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: "signed-in", uid: "u1", displayName: "Lead A" }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/outbox", () => ({ dismissItem: () => undefined }));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../training/session", () => ({ useTrainingSession: () => null }));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({ eventKey: state.eventKey }),
}));
vi.mock("../corrections/useCorrectedEntries", () => ({
  useCorrectedEntries: () => ({
    items: state.entries,
    ready: state.entriesReady,
    failed: false,
    correctionsFailed: false,
  }),
}));
vi.mock("./useAccuracyData", () => ({
  useOfficialCounts: () => state.official,
  useAccuracyMapping: () => state.mapping,
  saveMapping: (doc: unknown) => {
    state.saved.push(doc);
    return Promise.resolve("id");
  },
}));

import { Accuracy } from "./AccuracyPage";

const key = (n: number) => `2027test_qm${n}`;

function load(matches: number, sixthScout = "Scout F") {
  const alliances: AllianceFuel[] = [];
  const entries: unknown[] = [];
  for (let m = 1; m <= matches; m++) {
    alliances.push({
      matchKey: key(m),
      alliance: "red",
      teams: [1111, 2222, 3333],
      count: 52,
    });
    const scouts = ["Scout A", "Scout B", m === 1 ? sixthScout : "Scout C"];
    [1111, 2222, 3333].forEach((team, i) => {
      entries.push({
        id: `${m}-${team}`,
        tbaMatchKey: key(m),
        teamNumber: team,
        scoutedByName: scouts[i],
        fieldValues: { teleopFuelScored: 10 },
        rawValues: { teleopFuelScored: 10 },
      });
    });
  }
  state.official.alliances = alliances;
  state.entries = entries;
}

const view = () =>
  render(
    <MemoryRouter>
      <Accuracy />
    </MemoryRouter>,
  );

beforeEach(() => {
  setRoles(ready("strategy"));
  state.eventKey = "2027test";
  state.entries = [];
  state.entriesReady = true;
  state.official = {
    status: "ready",
    alliances: [],
    fetchedAt: null,
    problem: null,
    refresh: () => undefined,
  };
  state.mapping = { status: "ready", mapping: null };
  state.saved = [];
});
afterEach(cleanup);

describe("Accuracy", () => {
  it("lists each scout with an estimate, a robot count and a status word", () => {
    load(6);
    view();
    const table = screen.getByRole("table", { name: /Scouts by estimated/ });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(5);
    const a = rows.find((r) => within(r).queryByText("Scout A"));
    expect(a).toBeDefined();
    expect(within(a as HTMLElement).getByText("6")).toBeTruthy();
    expect(within(a as HTMLElement).getByText(/^\+\d\.\d$/)).toBeTruthy();
    expect(within(a as HTMLElement).getByText("Check in")).toBeTruthy();
  });

  it("marks a scout with too few robots instead of ranking them", () => {
    load(6);
    view();
    const f = screen.getByText("Scout F").closest("tr") as HTMLElement;
    expect(within(f).getByText("Not enough data")).toBeTruthy();
  });

  it("opens the matches behind a scout", () => {
    load(6);
    view();
    const toggle = screen.getByRole("button", { name: "Scout A" });
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    fireEvent.click(toggle);
    expect(toggle.getAttribute("aria-expanded")).toBe("true");
    const drill = screen.getByRole("table", { name: "Matches behind Scout A" });
    expect(within(drill).getAllByRole("row")).toHaveLength(7);
    const link = within(drill).getByRole("link", { name: "Q1" });
    expect(link.getAttribute("href")).toBe("/matches/2027test_qm1");
  });

  it("says when no played match has a breakdown yet", () => {
    view();
    expect(
      screen.getByText(/No played match has an official fuel count yet/),
    ).toBeTruthy();
    expect(screen.queryByRole("table", { name: /Scouts by/ })).toBeNull();
  });

  it("says when official counts could not be fetched and none are saved", () => {
    state.official.status = "failed";
    state.official.problem = "unreachable";
    view();
    expect(screen.getByRole("alert").textContent).toMatch(
      /could not be reached/,
    );
  });

  it("says when the event key has no matches at The Blue Alliance", () => {
    state.official.status = "failed";
    state.official.problem = "not-found";
    view();
    expect(screen.getByRole("alert").textContent).toMatch(
      /no matches for this event key/,
    );
  });

  it("keeps the table and warns when a refresh failed", () => {
    load(6);
    state.official.status = "failed";
    state.official.problem = "unreachable";
    view();
    expect(screen.getByText(/Refresh failed/)).toBeTruthy();
    expect(screen.getByRole("table", { name: /Scouts by/ })).toBeTruthy();
  });

  it("explains too few scouted alliances", () => {
    load(2);
    state.entries = state.entries.slice(0, 2);
    view();
    expect(screen.getByText(/No complete alliances yet/)).toBeTruthy();
    expect(screen.getByText(/2 alliances left out/)).toBeTruthy();
  });

  it("asks for an event first", () => {
    state.eventKey = "";
    view();
    expect(screen.getByText(/Choose an event in Settings/)).toBeTruthy();
  });

  it("offers to create a missing mapping and saves what was typed", async () => {
    view();
    fireEvent.click(screen.getByText("Alert mapping"));
    expect(screen.getByText("No mapping configured yet.")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Create mapping" }));
    const box = screen.getByLabelText("Mapping JSON") as HTMLTextAreaElement;
    expect(JSON.parse(box.value).mappings).toEqual([]);

    fireEvent.change(box, { target: { value: "{" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(screen.getByRole("alert").textContent).toMatch(/Not valid JSON/);
    expect(state.saved).toEqual([]);

    fireEvent.change(box, { target: { value: '{"year":2027,"mappings":[]}' } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await vi.waitFor(() =>
      expect(state.saved).toEqual([{ year: 2027, mappings: [] }]),
    );
  });

  it("shows the active mapping", () => {
    const mapping: MappingDoc = { year: 2026, mappings: [{}] };
    state.mapping = { status: "ready", mapping };
    view();
    fireEvent.click(screen.getByText("Alert mapping"));
    expect(screen.getByText("Compared fields")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Edit mapping" })).toBeTruthy();
  });
});
