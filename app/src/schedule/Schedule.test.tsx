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
import { myTeamStore } from "../now/myTeam";
import type { ScheduledMatch } from "../scout/schedule";
import { Schedule } from "./Schedule";

const state = vi.hoisted(() => ({
  data: {} as Record<string, unknown>,
}));

vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../accuracy/PredictionLine", () => ({
  PredictionLine: () => <p>Predictions so far</p>,
}));
vi.mock("../scout/ScoutData", () => ({ useScoutData: () => state.data }));

const qm = (
  n: number,
  scores?: [number, number],
  red = [1111, 2222, 3333],
): ScheduledMatch => ({
  key: `2027test_qm${n}`,
  compLevel: "qm",
  matchNumber: n,
  red,
  blue: [4444, 5555, 6666],
  time: 1_803_055_320 + n * 420,
  ...(scores ? { redScore: scores[0], blueScore: scores[1] } : {}),
});

function setData(patch: Record<string, unknown>) {
  state.data = {
    eventKey: "2027test",
    schedule: [qm(1, [50, 40]), qm(2, undefined, [7777, 8888, 9999]), qm(3)],
    scheduleFetchedAt: "2027-03-01T12:00:00.000Z",
    scheduleStatus: "ready",
    refreshSchedule: vi.fn(() => Promise.resolve()),
    ...patch,
  };
}

const show = () =>
  render(
    <MemoryRouter>
      <Schedule />
    </MemoryRouter>,
  );

beforeEach(() => {
  setRoles(ready("strategy"));
  setData({});
});

afterEach(() => {
  cleanup();
  localStorage.clear();
  myTeamStore.reload();
});

describe("Schedule", () => {
  it("splits upcoming and played with results", () => {
    show();
    const up = screen.getByRole("region", { name: /Upcoming/ });
    const played = screen.getByRole("region", { name: /Played/ });
    expect(within(up).getByText("Q2")).toBeTruthy();
    expect(within(up).getByText("Q3")).toBeTruthy();
    expect(within(played).getByText("Q1")).toBeTruthy();
    expect(within(played).getByText("Red won")).toBeTruthy();
    expect(within(played).getByText("50")).toBeTruthy();
    expect(within(played).getByText("40")).toBeTruthy();
  });

  it("links match labels for leads", () => {
    show();
    const link = screen.getByRole("link", { name: "Q2" });
    expect(link.getAttribute("href")).toBe("/matches/2027test_qm2");
  });

  it("shows plain labels and plain team numbers for scouts", () => {
    setRoles(ready("scouter"));
    show();
    expect(screen.queryByRole("link", { name: "Q2" })).toBeNull();
    expect(screen.queryByRole("link", { name: "1111" })).toBeNull();
    expect(screen.getByText("Q2")).toBeTruthy();
    expect(screen.queryByText("Predictions so far")).toBeNull();
  });

  it("shows the prediction line to leads", () => {
    show();
    expect(screen.getByText("Predictions so far")).toBeTruthy();
  });

  it("marks our matches and can show only those", () => {
    myTeamStore.set(1111);
    show();
    expect(screen.getAllByText(/Our match/)).toHaveLength(2);
    expect(screen.queryByText("Q2")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Team 1111 only" }));
    expect(screen.queryByText("Q2")).toBeNull();
    expect(screen.getByText("Q3")).toBeTruthy();
    expect(screen.getByText("Q1")).toBeTruthy();
  });

  it("filters to team 3847 when no team number is set", () => {
    show();
    expect(screen.getByRole("button", { name: /3847/ })).toBeTruthy();
  });

  it("says when no event is set", () => {
    setData({ eventKey: "", schedule: [] });
    show();
    expect(screen.getByText(/No event is set/)).toBeTruthy();
    expect(screen.getByRole("link", { name: "Open Settings" })).toBeTruthy();
  });

  it("says when the schedule is not out and offers a refresh", () => {
    const refreshSchedule = vi.fn(() => Promise.resolve());
    setData({ schedule: [], scheduleStatus: "ready", refreshSchedule });
    show();
    expect(screen.getByText(/is not out yet/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));
    expect(refreshSchedule).toHaveBeenCalled();
  });

  it("says when the schedule failed to load", () => {
    setData({ schedule: [], scheduleStatus: "failed" });
    show();
    expect(screen.getByText(/could not be loaded/)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
  });

  it("shows the cached schedule's age while offline", () => {
    const spy = vi.spyOn(navigator, "onLine", "get").mockReturnValue(false);
    show();
    expect(
      screen.getByText(/Offline\. Showing the schedule from/),
    ).toBeTruthy();
    expect(screen.getByText("Q1")).toBeTruthy();
    spy.mockRestore();
  });
});
