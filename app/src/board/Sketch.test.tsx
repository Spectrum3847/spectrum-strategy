// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { afterEach, describe, expect, it } from "vitest";
import { penColor } from "./model";
import { SketchEditor, SketchPreview, SketchToggle } from "./Sketch";
import { emptySketch, type Sketch } from "./sketch";

afterEach(cleanup);

const stroke = {
  phase: "auton" as const,
  legend: false,
  color: penColor,
  points: [
    { x: 0.1, y: 0.1 },
    { x: 0.5, y: 0.5 },
  ],
};

function Harness({ start }: { start: Sketch }) {
  const [value, setValue] = useState(start);
  return (
    <>
      <SketchEditor
        title="Report drawing"
        surface="Scouting drawing"
        value={value}
        phased
        onChange={setValue}
      />
      <output>{JSON.stringify(value)}</output>
    </>
  );
}

describe("SketchEditor", () => {
  it("labels the canvas with its phase and draws one line per phase", () => {
    render(<Harness start={emptySketch()} />);
    expect(
      screen.getByRole("group", {
        name: "Scouting drawing, Auto phase, empty",
      }),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Teleop" }));
    expect(
      screen.getByRole("group", {
        name: "Scouting drawing, Teleop phase, empty",
      }),
    ).toBeTruthy();
  });

  it("clears all drawings and disables Clear when empty", () => {
    render(<Harness start={{ ...emptySketch(), auton: [stroke] }} />);
    const clear = screen.getByRole("button", { name: "Clear" });
    expect((clear as HTMLButtonElement).disabled).toBe(false);
    fireEvent.click(clear);
    expect((clear as HTMLButtonElement).disabled).toBe(true);
    expect(
      screen
        .getByRole("group", { name: /Scouting drawing/ })
        .getAttribute("aria-label"),
    ).toContain("empty");
  });

  it("switches between draw and erase", () => {
    render(<Harness start={emptySketch()} />);
    const erase = screen.getByRole("button", { name: "Erase" });
    fireEvent.click(erase);
    expect(erase.getAttribute("aria-pressed")).toBe("true");
    expect(
      screen.getByRole("button", { name: "Draw" }).getAttribute("aria-pressed"),
    ).toBe("false");
  });
});

describe("SketchPreview", () => {
  it("shows nothing for an empty sketch", () => {
    const { container } = render(
      <SketchPreview surface="Scouting drawing" value={emptySketch()} phased />,
    );
    expect(container.textContent).toBe("");
  });

  it("offers a tab for each phase that has lines, read only", () => {
    render(
      <SketchPreview
        surface="Scouting drawing"
        value={{ ...emptySketch(), auton: [stroke], endgame: [stroke] }}
        phased
      />,
    );
    expect(screen.queryByRole("button", { name: "Teleop" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Endgame" }));
    expect(
      screen.getByRole("group", {
        name: "Scouting drawing, Endgame phase, 1 drawing, read only",
      }),
    ).toBeTruthy();
  });
});

describe("SketchToggle", () => {
  it("is absent without lines and folded with them", () => {
    const { container, rerender } = render(
      <SketchToggle
        surface="Trait drawing"
        value={emptySketch()}
        phased={false}
      />,
    );
    expect(container.querySelector("details")).toBeNull();
    rerender(
      <SketchToggle
        surface="Trait drawing"
        value={{ ...emptySketch(), auton: [stroke] }}
        phased={false}
      />,
    );
    expect(container.querySelector("details")?.hasAttribute("open")).toBe(
      false,
    );
  });
});
