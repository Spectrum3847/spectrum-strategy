// @vitest-environment jsdom
import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { PitScheduleView } from "./PitSchedule";
import { parsePitSchedule } from "./pit";

vi.mock("../firebase/client", () => ({ db: {} }));
afterEach(cleanup);

const schedule = parsePitSchedule({
  syncedAt: "2027-03-05T18:00:00.000Z",
  shifts: [
    {
      id: "a",
      label: "Pit duty",
      kind: "pitDuty",
      assignees: [{ name: "Scout A", uid: "u1" }],
      startMatch: 3,
      endMatch: 9,
    },
    { id: "b", label: "", kind: "loadOut", assignees: [], startMatch: 40 },
  ],
});

describe("PitScheduleView", () => {
  it("lists the shifts and counts the scout's own", () => {
    render(<PitScheduleView load="ready" schedule={schedule} uid="u1" />);
    expect(screen.getByRole("heading", { name: "Pit schedule" })).toBeTruthy();
    expect(screen.getByText(/2 shifts, 1 yours, synced/)).toBeTruthy();
    expect(screen.getByText("Pit duty")).toBeTruthy();
    expect(screen.getByText("Q3-9")).toBeTruthy();
    expect(screen.getByText("loadOut")).toBeTruthy();
    expect(screen.getByText("Unassigned")).toBeTruthy();
  });

  it("is absent when the event has no pit schedule", () => {
    const { container } = render(
      <PitScheduleView load="ready" schedule={null} uid="u1" />,
    );
    expect(container.textContent).toBe("");
  });

  it("says when it could not be read", () => {
    render(<PitScheduleView load="failed" schedule={null} uid="u1" />);
    expect(
      screen.getByText("The pit schedule could not be read."),
    ).toBeTruthy();
  });
});
