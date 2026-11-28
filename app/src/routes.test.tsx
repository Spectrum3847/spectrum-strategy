// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import { routes } from "./routes";

vi.mock("virtual:pwa-register/react", () => ({
  useRegisterSW: () => ({
    needRefresh: [false, () => undefined],
    offlineReady: [false, () => undefined],
    updateServiceWorker: () => Promise.resolve(),
  }),
}));
vi.mock("./auth/AuthProvider", () => ({
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
vi.mock("./auth/rolesContext", () =>
  import("./auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("./outbox/outbox", () => ({
  dismissFinished: () => undefined,
  dismissItem: () => undefined,
  enqueueProofEntry: () => Promise.resolve("id"),
  deleteProofEntries: () => Promise.resolve(0),
}));
vi.mock("./outbox/useOutbox", () => ({ useOutbox: () => [] }));

function renderAt(path: string) {
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  render(<RouterProvider router={router} />);
}

afterEach(cleanup);

describe("deep links", () => {
  it("renders a team page from /teams/:team", () => {
    renderAt("/teams/1234");
    expect(screen.getByRole("heading", { name: "Team 1234" })).toBeTruthy();
  });

  it("renders a match page from /matches/:key", () => {
    renderAt("/matches/2027test_qm12");
    expect(
      screen.getByRole("heading", { name: "Match 2027test_qm12" }),
    ).toBeTruthy();
  });

  it("renders the database from /database", () => {
    renderAt("/database");
    expect(screen.getByRole("heading", { name: "Database" })).toBeTruthy();
  });

  it("renders the settings list and a section from ?s=", () => {
    renderAt("/settings");
    expect(screen.getByRole("heading", { name: "Settings" })).toBeTruthy();
    cleanup();
    renderAt("/settings?s=data");
    expect(screen.getByRole("heading", { name: "Data" })).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Outbox" })).toBeTruthy();
  });

  it("falls through to not found for an unknown path", () => {
    renderAt("/no/such/page");
    expect(
      screen.getByRole("heading", { name: "Page not found" }),
    ).toBeTruthy();
  });
});
