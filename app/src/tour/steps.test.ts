// @vitest-environment jsdom
import { afterEach, describe, expect, it } from "vitest";
import { canOpenPath } from "../auth/roles";
import { markTourSeen, tourSeen, tourSteps } from "./steps";

const titles = (
  roles: Parameters<typeof tourSteps>[0],
  layout = "bar" as const,
) => tourSteps(roles, layout).map((s) => s.title);

describe("tourSteps", () => {
  it("gives a scouter the scouting screens only", () => {
    expect(titles(["scouter"])).toEqual([
      "Welcome to Spectrum Strategy",
      "Finding your way",
      "Now",
      "Scout",
      "Schedule",
      "Settings",
    ]);
  });

  it("gives a lead the analysis screens", () => {
    expect(titles(["strategy"])).toEqual([
      "Welcome to Spectrum Strategy",
      "Finding your way",
      "Now",
      "Scout",
      "Schedule",
      "Teams and matches",
      "Picks",
      "Settings",
    ]);
  });

  it("gives a mentor no Scout step and a brief-only match step", () => {
    const steps = tourSteps(["mentor"], "bar");
    expect(steps.map((s) => s.title)).not.toContain("Scout");
    expect(steps.find((s) => s.title === "Teams and matches")?.body).toContain(
      "brief in large type",
    );
  });

  it("adds Users for an admin only", () => {
    expect(titles(["admin"])).toContain("Users");
    expect(titles(["strategy"])).not.toContain("Users");
  });

  it("describes the navigation for the layout", () => {
    const nav = (l: "bar" | "rail" | "sidebar") =>
      tourSteps(["scouter"], l)[1]?.body ?? "";
    expect(nav("bar")).toContain("More");
    expect(nav("rail")).toContain("left");
    expect(nav("rail")).not.toContain("More");
    expect(nav("sidebar")).toContain("sidebar");
  });
});

describe("step routing", () => {
  const steps = (roles: Parameters<typeof tourSteps>[0]) =>
    tourSteps(roles, "bar");

  it("keeps the first two steps on the page the tour started on", () => {
    const [welcome, nav] = steps(["scouter"]);
    expect(welcome).toMatchObject({ to: null, nav: null });
    expect(nav).toMatchObject({ to: null, nav: "nav" });
  });

  it("opens and highlights the page each step is about", () => {
    const byTitle = Object.fromEntries(
      steps(["admin"]).map((s) => [s.title, s]),
    );
    for (const [title, path] of [
      ["Now", "/"],
      ["Scout", "/scout"],
      ["Schedule", "/schedule"],
      ["Teams and matches", "/teams"],
      ["Picks", "/picks"],
      ["Users", "/users"],
      ["Settings", "/settings"],
    ] as const) {
      expect(byTitle[title], title).toMatchObject({ to: path, nav: path });
    }
  });

  it("only opens pages the role can open", () => {
    const every = [
      ["scouter"],
      ["mentor"],
      ["mentor", "scouter"],
      ["strategy"],
      ["admin"],
      ["developer"],
    ] as const;
    for (const roles of every) {
      for (const step of steps([...roles])) {
        if (step.to !== null) {
          expect(canOpenPath([...roles], step.to), `${roles} ${step.to}`).toBe(
            true,
          );
        }
      }
    }
  });
});

describe("seen flag", () => {
  afterEach(() => localStorage.clear());

  it("starts unseen and stays seen", () => {
    expect(tourSeen()).toBe(false);
    markTourSeen();
    expect(tourSeen()).toBe(true);
  });

  it("reads as unseen when storage throws", () => {
    const get = Storage.prototype.getItem;
    Storage.prototype.getItem = () => {
      throw new Error("blocked");
    };
    try {
      expect(tourSeen()).toBe(false);
    } finally {
      Storage.prototype.getItem = get;
    }
  });
});
