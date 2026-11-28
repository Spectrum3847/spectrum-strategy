// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
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
  enqueueProofEntry: () => Promise.resolve("id"),
  enqueueWrite: () => Promise.resolve("id"),
  deleteProofEntries: () => Promise.resolve(0),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../scout/remote", () => ({
  watchScoutConfig: () => () => undefined,
  watchActiveEvent: () => () => undefined,
  watchEventEntries: () => () => undefined,
  fetchTbaKey: () => Promise.resolve(null),
}));

const view = (section = "") =>
  render(
    <RouterProvider
      router={createMemoryRouter(routes, {
        initialEntries: [`/settings${section && `?s=${section}`}`],
      })}
    />,
  );

afterEach(() => {
  cleanup();
  lockedStationStore.set(null);
});

describe("section list", () => {
  it("links each section and opens one with a back link", () => {
    setRoles(ready("scouter"));
    view();
    for (const name of [
      "Event",
      "This device",
      "Data",
      "Forms",
      "Account",
      "Help and about",
    ]) {
      expect(screen.getByRole("link", { name: new RegExp(name) })).toBeTruthy();
    }
    cleanup();
    view("device");
    expect(screen.getByRole("heading", { name: "This device" })).toBeTruthy();
    expect(document.querySelector(".settings-back")?.getAttribute("href")).toBe(
      "/settings",
    );
  });

  it("shows the list for an unknown section", () => {
    setRoles(ready("scouter"));
    view("nope");
    expect(screen.getByRole("heading", { name: "Settings" })).toBeTruthy();
  });
});

describe("help and about", () => {
  it("shows the version, credits and licenses", () => {
    setRoles(ready("scouter"));
    view("help");
    expect(
      screen.getByRole("heading", { name: "Version and device" }),
    ).toBeTruthy();
    expect(screen.getByText("App version")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Credits" })).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Licenses" })).toBeTruthy();
    const source = screen.getByRole("link", { name: /View source on GitHub/ });
    expect(source.getAttribute("rel")).toContain("noopener");
  });
});

describe("report a problem", () => {
  it("is on the page for a member", () => {
    setRoles(ready("scouter"));
    view("help");
    expect(
      screen.getByRole("heading", { name: "Report a problem" }),
    ).toBeTruthy();
  });
});

describe("forms", () => {
  it("gives a lead the editors", () => {
    setRoles(ready("strategy"));
    view("forms");
    expect(screen.getByRole("heading", { name: "Team forms" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Paste JSON" })).toBeTruthy();
  });

  it("gives a scout the forms to read and nothing to change", () => {
    setRoles(ready("scouter"));
    view("forms");
    expect(screen.getByRole("heading", { name: "Scout form" })).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Paste JSON" })).toBeNull();
  });
});

describe("station lock", () => {
  it("lets a lead lock and release the station", () => {
    setRoles(ready("strategy"));
    view("device");
    const r3 = screen.getByRole("button", { name: "R3" });
    expect(r3.hasAttribute("disabled")).toBe(false);
    r3.click();
    expect(lockedStationStore.get()).toBe("R3");
  });

  it("keeps a scout from moving or releasing the lock", () => {
    lockedStationStore.set("B2");
    setRoles(ready("scouter"));
    view("device");
    expect(screen.getByText(/Locked to B2. Only a strategy lead/)).toBeTruthy();
    for (const name of ["R1", "B2", "Not locked"]) {
      expect(
        screen.getByRole("button", { name }).hasAttribute("disabled"),
      ).toBe(true);
    }
  });
});
