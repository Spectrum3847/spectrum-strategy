// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { createMemoryRouter, RouterProvider } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Role } from "../auth/roles";
import { ready, setRoles } from "../auth/rolesMock";
import { routes } from "../routes";
import { layoutFor, splitTabs } from "./Shell";

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
  enqueueWrite: () => Promise.resolve("id"),
  dismissFinished: () => undefined,
  dismissItem: () => undefined,
  enqueueProofEntry: () => Promise.resolve("id"),
  deleteProofEntries: () => Promise.resolve(0),
}));
const outbox = vi.hoisted(() => ({ items: [] as { status: string }[] }));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => outbox.items }));
vi.mock("../scout/remote", () => ({
  watchScoutConfig: () => () => undefined,
  watchActiveEvent: () => () => undefined,
  watchEventEntries: () => () => undefined,
  fetchTbaKey: () => Promise.resolve(null),
}));

function renderAt(path: string, width: number) {
  window.innerWidth = width;
  const router = createMemoryRouter(routes, { initialEntries: [path] });
  render(<RouterProvider router={router} />);
  return router;
}

beforeEach(() => {
  localStorage.setItem("ss.tour.seen", "1");
});
afterEach(() => {
  cleanup();
  localStorage.clear();
  setRoles(ready("strategy"));
  outbox.items = [];
});

const bar = () => screen.getByRole("navigation", { name: "Main" });
const barItems = () =>
  [...bar().querySelectorAll("a, button")].map(
    (el) => el.querySelector(".nav-label")?.textContent,
  );
const moreButton = () => within(bar()).getByRole("button", { name: /^More/ });
const openMore = () => fireEvent.click(moreButton());
const sheetLabels = () =>
  within(screen.getByRole("dialog", { name: "More" }))
    .getAllByRole("link")
    .map((el) => el.textContent);

describe("layoutFor", () => {
  it("switches at 600 and 1024", () => {
    expect(layoutFor(599)).toBe("bar");
    expect(layoutFor(600)).toBe("rail");
    expect(layoutFor(1023)).toBe("rail");
    expect(layoutFor(1024)).toBe("sidebar");
  });
});

describe("navigation", () => {
  it.each([
    [390, "bar"],
    [820, "rail"],
    [1280, "sidebar"],
  ])("shows Now, Scout and Settings at %ipx as a %s", (width, layout) => {
    const { state } = renderAt("/scout", width);
    expect(state.location.pathname).toBe("/scout");
    const nav = screen.getByRole("navigation", { name: "Main" });
    expect(nav.parentElement?.getAttribute("data-layout")).toBe(layout);
    for (const name of layout === "bar"
      ? ["Now", "Scout"]
      : ["Now", "Scout", "Settings"]) {
      expect(within(nav).getByRole("link", { name })).toBeTruthy();
    }
    const current = within(nav).getByRole("link", { name: "Scout" });
    expect(current.getAttribute("aria-current")).toBe("page");
    expect(
      within(nav)
        .getByRole("link", { name: "Now" })
        .getAttribute("aria-current"),
    ).toBeNull();
  });

  it("follows a resize across the breakpoints", () => {
    renderAt("/", 390);
    const shell = () => document.querySelector(".shell");
    expect(shell()?.getAttribute("data-layout")).toBe("bar");
    act(() => {
      window.innerWidth = 700;
      window.dispatchEvent(new Event("resize"));
    });
    expect(shell()?.getAttribute("data-layout")).toBe("rail");
    act(() => {
      window.innerWidth = 1100;
      window.dispatchEvent(new Event("resize"));
    });
    expect(shell()?.getAttribute("data-layout")).toBe("sidebar");
  });

  it("collapses the sidebar to a rail and remembers it", () => {
    renderAt("/", 1280);
    act(() => {
      screen.getByRole("button", { name: "Collapse navigation" }).click();
    });
    expect(document.querySelector(".shell")?.getAttribute("data-layout")).toBe(
      "rail",
    );
    expect(localStorage.getItem("ss.nav.collapsed")).toBe("1");
  });

  it("opens the scout form on /scout", () => {
    renderAt("/scout", 390);
    expect(screen.getByRole("heading", { name: "Prematch" })).toBeTruthy();
  });
});

describe("splitTabs", () => {
  const t = (name: string, primary = false) => ({ name, primary });

  it("keeps four or fewer tabs in the bar", () => {
    const four = [t("a", true), t("b", true), t("c"), t("d")];
    expect(splitTabs(four)).toEqual({ bar: four, more: [] });
  });

  it("moves the non-primary tabs of a longer list under More", () => {
    const tabs = [t("a", true), t("b", true), t("c"), t("d"), t("e")];
    expect(splitTabs(tabs).bar.map((x) => x.name)).toEqual(["a", "b"]);
    expect(splitTabs(tabs).more.map((x) => x.name)).toEqual(["c", "d", "e"]);
  });
});

describe("phone bottom bar", () => {
  it.each<[Role, string[], string[]]>([
    ["scouter", ["Now", "Scout", "Schedule", "Settings"], []],
    [
      "strategy",
      ["Now", "Scout", "Teams", "Schedule", "More"],
      ["Picks", "Database", "AI", "Settings"],
    ],
    [
      "admin",
      ["Now", "Scout", "Teams", "Schedule", "More"],
      ["Picks", "Database", "AI", "Users", "Settings"],
    ],
  ])("gives %s the right bar and More list at 360px", (role, shown, rest) => {
    setRoles(ready(role));
    renderAt("/", 360);
    expect(barItems()).toEqual(shown);
    expect(barItems().length).toBeLessThanOrEqual(5);
    if (rest.length === 0) {
      expect(screen.queryByRole("button", { name: /^More/ })).toBeNull();
      return;
    }
    expect(screen.queryByRole("dialog")).toBeNull();
    openMore();
    expect(sheetLabels()).toEqual(rest);
  });

  it("marks More selected while one of its tabs is open", () => {
    setRoles(ready("admin"));
    renderAt("/", 360);
    expect(moreButton().getAttribute("aria-current")).toBeNull();
    openMore();
    fireEvent.click(
      within(screen.getByRole("dialog", { name: "More" })).getByRole("link", {
        name: "Users",
      }),
    );
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(moreButton().getAttribute("aria-current")).toBe("page");
    expect(moreButton().textContent).toContain("Users is open");
    expect(
      within(bar())
        .getByRole("link", { name: "Now" })
        .getAttribute("aria-current"),
    ).toBeNull();
  });

  it("reads More as selected on a deep link to one of its tabs", () => {
    setRoles(ready("strategy"));
    renderAt("/settings", 360);
    expect(moreButton().getAttribute("aria-current")).toBe("page");
    openMore();
    const dialog = screen.getByRole("dialog", { name: "More" });
    expect(
      within(dialog)
        .getByRole("link", { name: "Settings" })
        .getAttribute("aria-current"),
    ).toBe("page");
  });

  it("closes on Escape and returns focus to More", () => {
    renderAt("/", 360);
    const more = moreButton();
    more.focus();
    openMore();
    const dialog = screen.getByRole("dialog", { name: "More" });
    expect(dialog.contains(document.activeElement)).toBe(true);
    fireEvent.keyDown(document.activeElement ?? dialog, { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(document.activeElement).toBe(more);
  });

  it("closes with the close button", () => {
    renderAt("/", 360);
    openMore();
    fireEvent.click(screen.getByRole("button", { name: "Close" }));
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("keeps Tab inside the sheet", () => {
    renderAt("/", 360);
    openMore();
    const dialog = screen.getByRole("dialog", { name: "More" });
    const items = [...dialog.querySelectorAll<HTMLElement>("a, button")];
    const first = items[0];
    const last = items[items.length - 1];
    if (!first || !last) throw new Error("empty sheet");
    last.focus();
    fireEvent.keyDown(last, { key: "Tab" });
    expect(document.activeElement).toBe(first);
    fireEvent.keyDown(first, { key: "Tab", shiftKey: true });
    expect(document.activeElement).toBe(last);
  });

  it("keeps the unsent badge on Scout in the bar", () => {
    outbox.items = [{ status: "on-device" }, { status: "sending" }];
    renderAt("/", 360);
    const scout = within(bar()).getByRole("link", { name: /^Scout/ });
    expect(scout.textContent).toContain("2");
    expect(scout.textContent).toContain("2 entries not sent");
  });

  it("lists every tab in the rail at 820px, primary ones first", () => {
    setRoles(ready("admin"));
    renderAt("/", 820);
    expect(barItems()).toEqual([
      "Find",
      "Now",
      "Scout",
      "Teams",
      "Schedule",
      "Picks",
      "Database",
      "AI",
      "Users",
      "Settings",
    ]);
    expect(screen.queryByRole("button", { name: /^More/ })).toBeNull();
  });
});

describe("welcome tour", () => {
  it("shows once on a new device and is remembered", () => {
    localStorage.clear();
    renderAt("/", 360);
    const dialog = screen.getByRole("dialog", {
      name: "Welcome to Spectrum Strategy",
    });
    fireEvent.click(within(dialog).getByRole("button", { name: "Skip" }));
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(localStorage.getItem("ss.tour.seen")).toBe("1");
    cleanup();
    renderAt("/", 360);
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("opens again from Help and about", () => {
    renderAt("/settings?s=help", 360);
    expect(screen.queryByRole("dialog")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Show the tour" }));
    expect(
      screen.getByRole("dialog", { name: "Welcome to Spectrum Strategy" }),
    ).toBeTruthy();
  });
});

describe("jump to a team or match", () => {
  const find = () => screen.queryByRole("button", { name: "Find" });

  it("sits in the rail and opens a dialog", () => {
    renderAt("/", 820);
    fireEvent.click(find() as HTMLElement);
    expect(
      screen.getByRole("dialog", { name: "Go to team or match" }),
    ).toBeTruthy();
    fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
  });

  it("sits under More on a phone", () => {
    renderAt("/", 390);
    expect(find()).toBeNull();
    openMore();
    fireEvent.click(
      screen.getByRole("button", { name: "Find a team or match" }),
    );
    expect(
      screen.getByRole("dialog", { name: "Go to team or match" }),
    ).toBeTruthy();
  });

  it("opens from the keyboard, but not while typing in a field", () => {
    renderAt("/settings", 1280);
    const typing = document.createElement("input");
    document.body.append(typing);
    typing.focus();
    fireEvent.keyDown(typing, { key: "/" });
    expect(screen.queryByRole("dialog")).toBeNull();
    typing.blur();
    fireEvent.keyDown(document.body, { key: "/" });
    expect(
      screen.getByRole("dialog", { name: "Go to team or match" }),
    ).toBeTruthy();
    typing.remove();
    cleanup();
    renderAt("/settings", 1280);
    fireEvent.keyDown(document.body, { key: "k", ctrlKey: true });
    expect(
      screen.getByRole("dialog", { name: "Go to team or match" }),
    ).toBeTruthy();
  });

  it("is hidden from a scouter, who can open neither page", () => {
    setRoles(ready("scouter"));
    renderAt("/", 1280);
    expect(find()).toBeNull();
    fireEvent.keyDown(document.body, { key: "/" });
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});
