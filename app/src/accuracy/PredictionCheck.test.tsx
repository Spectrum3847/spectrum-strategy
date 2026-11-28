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
import bundled from "../../../assets/scout_config_default.json";
import { ready, setRoles } from "../auth/rolesMock";
import { parseConfig } from "../scout/config";
import { buildCheck, type Called } from "./predictionCheck";

const state = vi.hoisted(() => ({
  eventKey: "2027test",
  checks: {} as Record<string, unknown>,
  first: "tba",
  ready: true,
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: "signed-in", uid: "u1", displayName: "Lead A" }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../training/session", () => ({ useTrainingSession: () => null }));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({
    eventKey: state.eventKey,
    config: parseConfig(bundled),
  }),
}));
vi.mock("../corrections/useCorrectedEntries", () => ({
  useCorrectedEntries: () => ({ items: [], ready: true, failed: false }),
}));
vi.mock("./useAccuracyData", () => ({
  useOfficialCounts: () => ({ alliances: [] }),
}));
vi.mock("./usePredictionCheck", () => ({
  usePredictionCheck: () => ({
    eventKey: state.eventKey,
    ready: state.ready,
    checks: state.checks,
    firstWithMatches: state.first,
  }),
}));

import { PredictionCheck } from "./PredictionCheck";

const called = (
  n: number,
  redWin: number,
  scores: [number, number],
): Called => ({
  key: `2027test_qm${n}`,
  red: [1111, 2222, 3333],
  blue: [4444, 5555, 6666],
  redScore: scores[0],
  blueScore: scores[1],
  redWin,
  predRed: 60,
  predBlue: 40,
});

const view = () =>
  render(
    <MemoryRouter>
      <PredictionCheck />
    </MemoryRouter>,
  );

beforeEach(() => {
  setRoles(ready("strategy"));
  state.eventKey = "2027test";
  state.ready = true;
  state.first = "tba";
  state.checks = {
    tba: buildCheck(
      [
        ...Array.from({ length: 9 }, (_, i) => called(i + 1, 0.95, [62, 41])),
        called(10, 0.95, [30, 70]),
      ],
      1111,
    ),
    scouting: buildCheck([], 1111),
  };
});
afterEach(cleanup);

describe("prediction check", () => {
  it("shows how often the favourite won and the score miss", () => {
    view();
    expect(screen.getAllByText("90%").length).toBeGreaterThan(0);
    expect(screen.getByText("9 of 10 matches")).toBeTruthy();
    expect(screen.getByText("points per alliance, on average")).toBeTruthy();
    expect(screen.queryByText(/Too early to judge/)).toBeNull();
  });

  it("gives a verdict for each band", () => {
    view();
    const table = screen.getByRole("table");
    expect(within(table).getByText("90-100%")).toBeTruthy();
    expect(within(table).getByText("about right")).toBeTruthy();
  });

  it("lists our matches and the biggest misses, each linking to its match", () => {
    view();
    const ours = screen
      .getByRole("heading", { name: "Our matches" })
      .closest("section") as HTMLElement;
    expect(
      within(ours)
        .getAllByRole("link", { name: "Q10" })[0]
        ?.getAttribute("href"),
    ).toBe("/matches/2027test_qm10");
    expect(within(ours).getAllByText("Favourite lost").length).toBe(1);
    const misses = screen
      .getByRole("heading", { name: "Biggest misses" })
      .closest("section") as HTMLElement;
    expect(within(misses).getAllByRole("link")[0]?.textContent).toBe("Q10");
    expect(
      within(misses).getAllByText("Close to the forecast.").length,
    ).toBeGreaterThan(0);
  });

  it("says too early to judge under ten matches", () => {
    state.checks = {
      tba: buildCheck([called(1, 0.7, [60, 40])], null),
      scouting: buildCheck([], null),
    };
    view();
    expect(
      screen.getByText(/Too early to judge: 1 played match\./),
    ).toBeTruthy();
  });

  it("checks our scouting on its own with no score to compare", () => {
    state.checks = {
      tba: buildCheck([], null),
      scouting: buildCheck(
        [{ ...called(1, 0.7, [60, 40]), predRed: null, predBlue: null }],
        null,
      ),
    };
    state.first = "scouting";
    view();
    expect(
      screen.getByText(/Scouted fuel is not official points/),
    ).toBeTruthy();
    expect(
      screen.queryByRole("heading", { name: "Biggest misses" }),
    ).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "The Blue Alliance" }));
    expect(
      screen.getByText(
        "No played match has a prediction from The Blue Alliance yet.",
      ),
    ).toBeTruthy();
  });

  it("asks for an event first", () => {
    state.eventKey = "";
    view();
    expect(screen.getByText("Choose an event in Settings first.")).toBeTruthy();
  });
});
