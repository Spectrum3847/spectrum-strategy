// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
} from "@testing-library/react";
import { MemoryRouter, useLocation } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { TourStep } from "./steps";
import { Tour } from "./Tour";

const steps: TourStep[] = [
  { title: "One", body: "First.", to: null, nav: null },
  { title: "Two", body: "Second.", to: "/scout", nav: "/scout" },
  { title: "Three", body: "Third.", to: "/schedule", nav: "nav" },
];

afterEach(cleanup);

function Where() {
  const l = useLocation();
  return <p data-testid="where">{`${l.pathname}${l.search}`}</p>;
}

const open = (start = "/settings?s=help") => {
  const onClose = vi.fn();
  render(
    <MemoryRouter initialEntries={[start]}>
      <nav>
        <a href="/scout" data-tour-tab="/scout">
          Scout
        </a>
      </nav>
      <Where />
      <Tour
        steps={steps}
        layout="bar"
        barPaths={["/scout"]}
        onClose={onClose}
      />
    </MemoryRouter>,
  );
  return onClose;
};

const where = () => screen.getByTestId("where").textContent;

describe("Tour", () => {
  it("is a labelled modal dialog on the first step, with focus on its title", () => {
    open();
    const dialog = screen.getByRole("dialog", { name: "One" });
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(screen.getByText("Step 1 of 3")).toBeTruthy();
    expect(document.activeElement).toBe(
      screen.getByRole("heading", { name: "One" }),
    );
    expect(screen.queryByRole("button", { name: "Back" })).toBeNull();
  });

  it("steps forward and back, then finishes", () => {
    const onClose = open();
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(screen.getByRole("dialog", { name: "Two" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(screen.getByRole("dialog", { name: "One" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(screen.queryByRole("button", { name: "Skip" })).toBeNull();
    expect(onClose).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Done" }));
    expect(onClose).toHaveBeenCalledOnce();
  });

  it("closes on Skip and on Escape", () => {
    const onClose = open();
    fireEvent.click(screen.getByRole("button", { name: "Skip" }));
    fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it("goes back to the start on Escape pressed before a step's page renders", () => {
    const onClose = open();
    const dialog = screen.getByRole("dialog");
    act(() => {
      fireEvent.click(screen.getByRole("button", { name: "Next" }));
      fireEvent.keyDown(dialog, { key: "Escape" });
    });
    expect(onClose).toHaveBeenCalledOnce();
    expect(where()).toBe("/settings?s=help");
  });

  it("keeps Tab inside the dialog", () => {
    open();
    const done = screen.getByRole("button", { name: "Next" });
    done.focus();
    fireEvent.keyDown(done, { key: "Tab" });
    expect(document.activeElement).toBe(
      screen.getByRole("button", { name: "Skip" }),
    );
    fireEvent.keyDown(document.activeElement as Element, {
      key: "Tab",
      shiftKey: true,
    });
    expect(document.activeElement).toBe(done);
  });

  it("opens each step's page and goes back to the start when it ends", () => {
    const onClose = open();
    expect(where()).toBe("/settings?s=help");
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(where()).toBe("/scout");
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    expect(where()).toBe("/schedule");
    fireEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(where()).toBe("/scout");
    fireEvent.click(screen.getByRole("button", { name: "Back" }));
    expect(where()).toBe("/settings?s=help");
    fireEvent.click(screen.getByRole("button", { name: "Next" }));
    fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
    expect(where()).toBe("/settings?s=help");
    expect(onClose).toHaveBeenCalledOnce();
  });

  it("rings the nav item with a hidden spotlight and keeps the card clear of it", () => {
    const rect = { left: 10, top: 600, width: 80, height: 56 };
    const original = HTMLElement.prototype.getBoundingClientRect;
    HTMLElement.prototype.getBoundingClientRect = () =>
      ({
        ...rect,
        right: 90,
        bottom: 656,
        x: 10,
        y: 600,
        toJSON: () => rect,
      }) as DOMRect;
    try {
      open();
      expect(screen.queryByTestId("tour-ring")).toBeNull();
      fireEvent.click(screen.getByRole("button", { name: "Next" }));
      const ring = screen.getByTestId("tour-ring");
      expect(ring.getAttribute("aria-hidden")).toBe("true");
      expect(ring.style.top).toBe("596px");
      const dialog = screen.getByRole("dialog");
      expect(dialog.closest(".tour-scrim")?.getAttribute("data-place")).toBe(
        "top",
      );
      expect(dialog.style.maxHeight).toBe("564px");
    } finally {
      HTMLElement.prototype.getBoundingClientRect = original;
    }
  });
});
