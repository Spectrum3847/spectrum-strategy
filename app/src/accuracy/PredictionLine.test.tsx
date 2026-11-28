// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { buildCheck, type Called } from "./predictionCheck";

const state = vi.hoisted(() => ({ checks: {} as Record<string, unknown> }));

vi.mock("./usePredictionCheck", () => ({
  usePredictionCheck: () => ({
    checks: state.checks,
    firstWithMatches: "tba",
  }),
}));

import { PredictionLine } from "./PredictionLine";

const called = (n: number): Called => ({
  key: `2027test_qm${n}`,
  red: [1111, 2222, 3333],
  blue: [4444, 5555, 6666],
  redScore: 60,
  blueScore: 40,
  redWin: 0.8,
  predRed: 50,
  predBlue: 40,
});

const view = () =>
  render(
    <MemoryRouter>
      <PredictionLine />
    </MemoryRouter>,
  );

beforeEach(() => {
  state.checks = { tba: buildCheck([], null) };
});
afterEach(cleanup);

describe("prediction line", () => {
  it("says nothing before a prediction can be checked", () => {
    view();
    expect(screen.queryByRole("link")).toBeNull();
  });

  it("says too early below ten matches", () => {
    state.checks = { tba: buildCheck([called(1)], null) };
    view();
    expect(
      screen.getByText(/too early to judge, 1 played and 10 needed/),
    ).toBeTruthy();
  });

  it("gives the record and links to the check", () => {
    state.checks = {
      tba: buildCheck(
        Array.from({ length: 10 }, (_, i) => called(i + 1)),
        null,
      ),
    };
    view();
    expect(
      screen.getByText(
        /the favourite won 10 of 10 \(100%\), scores off by 5 points/,
      ),
    ).toBeTruthy();
    expect(
      screen
        .getByRole("link", { name: "Prediction check" })
        .getAttribute("href"),
    ).toBe("/scout/accuracy/predictions");
  });
});
