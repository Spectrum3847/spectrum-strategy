// @vitest-environment jsdom
import { cleanup, render, screen, within } from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { routes } from "../routes";
import { lockedStationStore } from "../scout/local";

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
  enqueueWrite: () => Promise.resolve("id"),
  enqueueProofEntry: () => Promise.resolve("id"),
  deleteProofEntries: () => Promise.resolve(0),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../scout/remote", () => ({
  watchScoutConfig: () => () => undefined,
  watchActiveEvent: () => () => undefined,
  watchEventEntries: () => () => undefined,
  fetchTbaKey: () => Promise.resolve(null),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({ items: [], ready: true, failed: false }),
}));
vi.mock("../data/useCorrections", () => ({
  useCorrections: () => ({ items: [], ready: true, failed: false }),
}));
vi.mock("../data/useCollections", async (importActual) => {
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const { parseConfig } = await import("../scout/config");
  return {
    ...(await importActual<typeof import("../data/useCollections")>()),
    usePitEntries: () => ({ items: [], ready: true, failed: false }),
    useFormConfig: () => parseConfig(pit.default),
  };
});
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "",
    status: "none",
    fetchedAt: null,
    teams: [],
    rankings: [],
    matches: [],
  }),
}));
vi.mock("../match/useOutside", async (importActual) => ({
  ...(await importActual<typeof import("../match/useOutside")>()),
  useEpa: () => ({ status: "none", data: null }),
}));

function renderAt(path: string) {
  window.innerWidth = 1280;
  render(
    <RouterProvider
      router={createMemoryRouter(routes, { initialEntries: [path] })}
    />,
  );
}

const nav = () => screen.getByRole("navigation", { name: "Main" });

afterEach(() => {
  cleanup();
  localStorage.clear();
  lockedStationStore.set(null);
  setRoles(ready("strategy"));
});

describe.each([
  { tab: "Teams", path: "/teams" },
  { tab: "Picks", path: "/picks" },
])("the $tab tab", ({ tab, path }) => {
  it.each(["strategy", "admin", "developer"] as const)(
    "is in the navigation for %s",
    (role) => {
      setRoles(ready(role));
      renderAt("/");
      expect(within(nav()).getByRole("link", { name: tab })).toBeTruthy();
    },
  );

  it("is not shown to a scouter, and its route says not available", () => {
    setRoles(ready("scouter"));
    renderAt(path);
    expect(within(nav()).queryByRole("link", { name: tab })).toBeNull();
    expect(
      screen.getByRole("heading", { name: "Not available for your role" }),
    ).toBeTruthy();
    expect(screen.queryByRole("heading", { name: tab })).toBeNull();
  });

  it("opens for a lead and marks the tab current", () => {
    renderAt(path);
    expect(screen.getByRole("heading", { name: tab })).toBeTruthy();
    expect(
      within(nav())
        .getByRole("link", { name: tab })
        .getAttribute("aria-current"),
    ).toBe("page");
  });
});

describe("team compare route", () => {
  it("says not available to a scouter", () => {
    setRoles(ready("scouter"));
    renderAt("/teams/compare?t=1111,2222");
    expect(
      screen.getByRole("heading", { name: "Not available for your role" }),
    ).toBeTruthy();
  });

  it("opens Compare, not the Team page for a team called compare", () => {
    renderAt("/teams/compare");
    expect(screen.getByRole("heading", { name: "Compare teams" })).toBeTruthy();
    expect(screen.queryByText(/not a team number/)).toBeNull();
  });
});
