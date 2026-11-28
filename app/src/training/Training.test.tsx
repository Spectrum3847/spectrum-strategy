// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { routes } from "../routes";
import type { ScheduledMatch } from "../scout/schedule";

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
  enqueueWrite: () => Promise.reject(new Error("outbox used")),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../scout/remote", () => ({
  watchScoutConfig: () => () => undefined,
  watchActiveEvent: () => () => undefined,
  watchEventEntries: () => () => undefined,
  fetchTbaKey: () => Promise.resolve(null),
}));
const load = vi.hoisted(() => vi.fn());
vi.mock("./load", async (importActual) => ({
  ...(await importActual<typeof import("./load")>()),
  loadReplay: load,
}));

import { buildReplay } from "./replay";
import {
  isTraining,
  leaveTraining,
  playNextMatch,
  startTraining,
} from "./session";

const match = (n: number, redScore: number, blueScore: number) =>
  ({
    key: `2026test_qm${n}`,
    compLevel: "qm",
    matchNumber: n,
    red: [1111, 2222, 3333],
    blue: [4444, 5555, 6666],
    redScore,
    blueScore,
  }) as ScheduledMatch;

const replay = () =>
  buildReplay(
    [match(1, 50, 20), match(2, 10, 40)],
    [{ number: 1111, nickname: "Alpha" }],
  );

const view = (path: string) =>
  render(
    <RouterProvider
      router={createMemoryRouter(routes, { initialEntries: [path] })}
    />,
  );

beforeEach(() => {
  localStorage.clear();
  load.mockResolvedValue(replay());
});

afterEach(() => {
  cleanup();
  leaveTraining();
});

describe("training banner", () => {
  it("shows on every screen while training and not otherwise", async () => {
    setRoles(ready("strategy"));
    startTraining("2026test", replay());
    for (const path of ["/", "/schedule", "/settings"]) {
      view(path);
      expect(
        await screen.findByText(
          /past event 2026test, nothing is saved to the team database/,
        ),
      ).toBeTruthy();
      cleanup();
    }
    leaveTraining();
    view("/settings");
    await screen.findByRole("heading", { name: "Settings" });
    expect(
      screen.queryByText(/nothing is saved to the team database/),
    ).toBeNull();
  });

  it("lets anyone leave training from the banner", async () => {
    setRoles(ready("scouter"));
    startTraining("2026test", replay());
    view("/");
    (await screen.findByRole("button", { name: "Leave training" })).click();
    await waitFor(() => expect(isTraining()).toBe(false));
  });
});

describe("Settings panel", () => {
  it("lets a lead start, play the next match and leave", async () => {
    setRoles(ready("strategy"));
    view("/settings?s=event");
    const input = await screen.findByLabelText("Past event key");
    fireEvent.change(input, { target: { value: "2026test" } });
    screen.getByRole("button", { name: "Start training" }).click();
    expect(await screen.findByText("0 of 2 matches")).toBeTruthy();
    expect(screen.getByText("Q1")).toBeTruthy();
    screen.getByRole("button", { name: "Play next match" }).click();
    expect(await screen.findByText("1 of 2 matches")).toBeTruthy();
    screen.getAllByRole("button", { name: "Leave training" })[0]?.click();
    await waitFor(() => expect(isTraining()).toBe(false));
  });

  it("lets a scout start training and play the next match", async () => {
    setRoles(ready("scouter"));
    view("/settings?s=event");
    const input = await screen.findByLabelText("Past event key");
    fireEvent.change(input, { target: { value: "2026test" } });
    screen.getByRole("button", { name: "Start training" }).click();
    expect(await screen.findByText("0 of 2 matches")).toBeTruthy();
    screen.getByRole("button", { name: "Play next match" }).click();
    expect(await screen.findByText("1 of 2 matches")).toBeTruthy();
  });
});

describe("Schedule while training", () => {
  it("shows results only for the matches played so far", async () => {
    setRoles(ready("strategy"));
    startTraining("2026test", replay());
    view("/schedule");
    expect(await screen.findByText("Q1")).toBeTruthy();
    expect(screen.queryByText("Red won")).toBeNull();
    cleanup();
    playNextMatch();
    view("/schedule");
    expect(await screen.findByText("Red won")).toBeTruthy();
    expect(screen.queryByText("Blue won")).toBeNull();
  });
});
