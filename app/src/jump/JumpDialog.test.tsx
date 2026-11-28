// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { JumpDialog } from "./JumpDialog";

vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027test",
    teams: [
      { number: 1111, nickname: "Alpha" },
      { number: 2222, nickname: "Beta" },
    ],
    matches: [{ key: "2027test_qm45" }, { key: "2027test_sf2m1" }],
  }),
}));

function Where() {
  return <p data-testid="where">{useLocation().pathname}</p>;
}

function Harness({ onClose }: { onClose(): void }) {
  return (
    <MemoryRouter>
      <button type="button">Opener</button>
      <JumpDialog onClose={onClose} />
      <Routes>
        <Route path="*" element={<Where />} />
      </Routes>
    </MemoryRouter>
  );
}

const field = () => screen.getByLabelText("Team number or match");
const type = (value: string) =>
  fireEvent.change(field(), { target: { value } });

beforeEach(() => setRoles(ready("strategy")));
afterEach(cleanup);

describe("jump dialog", () => {
  it("focuses the field and opens a team on Go", () => {
    const onClose = vi.fn();
    render(<Harness onClose={onClose} />);
    expect(document.activeElement).toBe(field());
    type("1111");
    fireEvent.click(screen.getByRole("button", { name: "Go" }));
    expect(screen.getByTestId("where").textContent).toBe("/teams/1111");
    expect(onClose).toHaveBeenCalled();
  });

  it("opens a match typed as q45, and shows it as a result first", () => {
    render(<Harness onClose={() => undefined} />);
    type("q45");
    expect(
      screen.getByRole("button", { name: /Qualification 45/ }),
    ).toBeTruthy();
    fireEvent.submit(field().closest("form") as HTMLFormElement);
    expect(screen.getByTestId("where").textContent).toBe(
      "/matches/2027test_qm45",
    );
  });

  it("shows a message in place for an unknown team or match", () => {
    render(<Harness onClose={() => undefined} />);
    type("9999");
    fireEvent.click(screen.getByRole("button", { name: "Go" }));
    expect(screen.getByRole("alert").textContent).toBe(
      "Team 9999 is not at this event.",
    );
    expect(field().getAttribute("aria-invalid")).toBe("true");
    type("q99");
    expect(screen.queryByRole("alert")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Go" }));
    expect(screen.getByRole("alert").textContent).toContain(
      "not in the schedule",
    );
    expect(screen.getByTestId("where").textContent).toBe("/");
  });

  it("closes on Escape and gives focus back", () => {
    const onClose = vi.fn();
    const { unmount } = render(<Harness onClose={onClose} />);
    fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
    expect(onClose).toHaveBeenCalled();
    unmount();
  });

  it("returns focus to what opened it", () => {
    const opener = document.createElement("button");
    document.body.append(opener);
    opener.focus();
    const { unmount } = render(<Harness onClose={() => undefined} />);
    expect(document.activeElement).not.toBe(opener);
    unmount();
    expect(document.activeElement).toBe(opener);
    opener.remove();
  });

  it("opens a match for a mentor", () => {
    setRoles(ready("mentor"));
    render(<Harness onClose={() => undefined} />);
    type("q45");
    fireEvent.click(screen.getByRole("button", { name: "Go" }));
    expect(screen.getByTestId("where").textContent).toBe(
      "/matches/2027test_qm45",
    );
  });
});
