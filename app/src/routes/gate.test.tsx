// @vitest-environment jsdom
import { cleanup, render, screen, within } from "@testing-library/react";
import {
  createMemoryRouter,
  type RouteObject,
  RouterProvider,
} from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { routes } from "../routes";

const outbox = vi.hoisted(() => ({
  items: [] as { path: string; status: string }[],
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
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => outbox.items }));
vi.mock("../scout/remote", () => ({
  watchScoutConfig: () => () => undefined,
  watchActiveEvent: () => () => undefined,
  watchEventEntries: () => () => undefined,
  fetchTbaKey: () => Promise.resolve(null),
}));

vi.mock("../users/useProfiles", () => ({
  useProfiles: () => ({
    items: [],
    ready: false,
    failed: false,
    code: null,
    fromCache: false,
    count: 0,
  }),
  saveProfileWrites: () => Promise.resolve(),
}));

const withExtra: RouteObject[] = [
  {
    element: routes[0]?.element,
    children: [
      ...(routes[0]?.children ?? []),
      { path: "scout/extra", element: <h1>Extra form</h1> },
    ],
  },
];

function renderAt(path: string, tree = routes) {
  window.innerWidth = 1280;
  render(
    <RouterProvider
      router={createMemoryRouter(tree, { initialEntries: [path] })}
    />,
  );
}

const nav = () => screen.getByRole("navigation", { name: "Main" });

afterEach(() => {
  cleanup();
  localStorage.clear();
  outbox.items = [];
  setRoles(ready("strategy"));
});

describe("before roles are known", () => {
  it("shows a loading state, never the no-access screen", () => {
    setRoles({ status: "loading", retry: () => undefined });
    renderAt("/");
    expect(
      screen.getByRole("heading", { name: "Loading your access" }),
    ).toBeTruthy();
    expect(screen.queryByRole("heading", { name: "No access" })).toBeNull();
    expect(screen.queryByRole("navigation", { name: "Main" })).toBeNull();
  });

  it("offers sign-in when signed out", () => {
    setRoles({ status: "signed-out", retry: () => undefined });
    renderAt("/");
    expect(
      screen.getByRole("heading", { name: "You are signed out" }),
    ).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "Sign in with Google" }),
    ).toBeTruthy();
  });

  it("says the roles could not be checked, which is not no access", () => {
    setRoles({ status: "unavailable", retry: () => undefined });
    renderAt("/");
    expect(
      screen.getByRole("heading", { name: "Your access could not be checked" }),
    ).toBeTruthy();
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
    expect(screen.queryByRole("heading", { name: "No access" })).toBeNull();
  });
});

describe("a profile with no granting role", () => {
  it("sees the no-access screen and no navigation", () => {
    setRoles(ready("viewer"));
    renderAt("/");
    expect(screen.getByRole("heading", { name: "No access" })).toBeTruthy();
    expect(screen.getByText(/Ask an admin/)).toBeTruthy();
    expect(screen.queryByRole("navigation", { name: "Main" })).toBeNull();
  });
});

describe("a scouter", () => {
  it("sees Now, Scout, Schedule and Settings", () => {
    setRoles(ready("scouter"));
    renderAt("/");
    for (const name of ["Now", "Scout", "Schedule", "Settings"]) {
      expect(within(nav()).getByRole("link", { name })).toBeTruthy();
    }
  });

  it("opens the schedule", () => {
    setRoles(ready("scouter"));
    renderAt("/schedule");
    expect(screen.getByRole("heading", { name: "Schedule" })).toBeTruthy();
  });

  it("gets a polite page instead of the team page", () => {
    setRoles(ready("scouter"));
    renderAt("/teams/1111");
    expect(
      screen.getByRole("heading", { name: "Not available for your role" }),
    ).toBeTruthy();
    expect(screen.queryByRole("heading", { name: "Team 1111" })).toBeNull();
    expect(within(nav()).getByRole("link", { name: "Now" })).toBeTruthy();
  });

  it("gets the same page instead of the match page", () => {
    setRoles(ready("scouter"));
    renderAt("/matches/2027test_qm1");
    expect(
      screen.getByRole("heading", { name: "Not available for your role" }),
    ).toBeTruthy();
  });

  it("opens routes added under /scout without a gating change", () => {
    setRoles(ready("scouter"));
    renderAt("/scout/extra", withExtra);
    expect(screen.getByRole("heading", { name: "Extra form" })).toBeTruthy();
  });

  it("still gets not found for a path that does not exist", () => {
    setRoles(ready("scouter"));
    renderAt("/no/such/page");
    expect(
      screen.getByRole("heading", { name: "Page not found" }),
    ).toBeTruthy();
  });
});

describe("a lead", () => {
  it.each(["strategy", "admin", "developer"] as const)(
    "opens the team page as %s",
    (role) => {
      setRoles(ready(role));
      renderAt("/teams/1111");
      expect(screen.getByRole("heading", { name: "Team 1111" })).toBeTruthy();
    },
  );

  it("has both roles of a person who holds two", () => {
    setRoles(ready("scouter", "admin"));
    renderAt("/matches/2027test_qm1");
    expect(
      screen.getByRole("heading", { name: "Match 2027test_qm1" }),
    ).toBeTruthy();
  });
});

describe("a mentor", () => {
  it("sees the pages that read and none that scout or manage", () => {
    setRoles(ready("mentor"));
    renderAt("/");
    for (const name of [
      "Now",
      "Teams",
      "Schedule",
      "Picks",
      "Database",
      "Settings",
    ]) {
      expect(within(nav()).getByRole("link", { name }), name).toBeTruthy();
    }
    for (const name of ["Scout", "Users"]) {
      expect(within(nav()).queryByRole("link", { name }), name).toBeNull();
    }
  });

  it("opens the team page and the match page", () => {
    setRoles(ready("mentor"));
    renderAt("/teams/1111");
    expect(screen.getByRole("heading", { name: "Team 1111" })).toBeTruthy();
    cleanup();
    renderAt("/matches/2027test_qm1");
    expect(
      screen.getByRole("heading", { name: "Match 2027test_qm1" }),
    ).toBeTruthy();
  });

  it.each(["/scout", "/scout/shifts", "/users"])(
    "gets the polite page for %s",
    (path) => {
      setRoles(ready("mentor"));
      renderAt(path);
      expect(
        screen.getByRole("heading", { name: "Not available for your role" }),
      ).toBeTruthy();
    },
  );
});

describe("the Users page", () => {
  it("is in the nav and opens for an admin", () => {
    setRoles(ready("admin"));
    renderAt("/users");
    expect(within(nav()).getByRole("link", { name: "Users" })).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Users" })).toBeTruthy();
  });

  it.each(["strategy", "developer", "scouter"] as const)(
    "is hidden from %s and says it is for admin accounts",
    (role) => {
      setRoles(ready(role));
      renderAt("/users");
      expect(within(nav()).queryByRole("link", { name: "Users" })).toBeNull();
      expect(
        screen.getByRole("heading", { name: "Not available for your role" }),
      ).toBeTruthy();
      expect(screen.getByText(/for admin accounts/)).toBeTruthy();
    },
  );
});

describe("unsent entries", () => {
  it("mark Scout with a count and show a banner elsewhere", () => {
    outbox.items = [
      { path: "scoutEntries/a", status: "on-device" },
      { path: "scoutEntries/b", status: "refused" },
    ];
    setRoles(ready("scouter"));
    renderAt("/");
    expect(
      within(nav()).getByRole("link", { name: /Scout.*2 entries not sent/ }),
    ).toBeTruthy();
    const banner = screen.getByRole("status");
    expect(banner.textContent).toContain("1 entry is saved on this device");
    expect(banner.textContent).toContain("1 entry was refused");
  });

  it("show no banner on the Scout tab, which has its own status line", () => {
    outbox.items = [{ path: "scoutEntries/a", status: "on-device" }];
    setRoles(ready("scouter"));
    renderAt("/scout");
    expect(
      screen.queryByText(/saved on this device and not in the database/),
    ).toBe(null);
  });

  it("show nothing when everything is in the database", () => {
    outbox.items = [{ path: "scoutEntries/a", status: "in-database" }];
    renderAt("/");
    expect(screen.queryByRole("status")).toBeNull();
    expect(within(nav()).getByRole("link", { name: "Scout" })).toBeTruthy();
  });
});
