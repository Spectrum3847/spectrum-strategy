// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, expect, it, vi } from "vitest";
import { Bracket } from "./Bracket";

vi.mock("../ui/TeamLink", () => ({
  TeamLink: ({ team }: { team: number }) => <span>{team}</span>,
}));

afterEach(cleanup);
it("moves the bracket without starting playback", () => {
  const alliances = Array.from({ length: 8 }, (_, i) => [
    i * 3 + 1,
    i * 3 + 2,
    i * 3 + 3,
  ]);
  render(
    <MemoryRouter>
      <Bracket alliances={alliances} robots={new Map()} />
    </MemoryRouter>,
  );
  fireEvent.change(screen.getByLabelText("Simulate through"), {
    target: { value: "6" },
  });
  expect(
    screen.getAllByText("Match 6", { selector: "strong" }).length,
  ).toBeGreaterThan(0);
  expect(screen.getByRole("button", { name: "Play" })).toBeTruthy();
  fireEvent.click(screen.getByRole("button", { name: "Play" }));
  expect(screen.getByRole("button", { name: "Pause" })).toBeTruthy();
});
