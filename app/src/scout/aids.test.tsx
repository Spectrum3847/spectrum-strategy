// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { PitEntry } from "../data/parse";
import { AlertBanner } from "./AlertBanner";
import { parseConfig } from "./config";
import { newestPit, PitBar } from "./PitBar";
import { PreEventCard, showPreEvent } from "./PreEventCard";

vi.mock("../photos/service", () => import("../photos/fakeService"));
afterEach(cleanup);

const config = parseConfig({
  sections: [
    {
      name: "Pit",
      fields: [{ code: "drive", title: "Drivetrain", type: "text" }],
    },
  ],
});

const pit = (
  id: string,
  team: number,
  at: string,
  drive: string,
): PitEntry => ({
  id,
  teamNumber: team,
  eventKey: "2027test",
  fieldValues: { drive },
  authorUid: "u1",
  scoutName: "Scout A",
  updatedAt: at,
  photoKeys: [],
});

describe("PitBar", () => {
  const entries = [
    pit("a", 1111, "2027-03-01T10:00:00Z", "Tank"),
    pit("b", 1111, "2027-03-02T10:00:00Z", "Swerve"),
    pit("c", 2222, "2027-03-03T10:00:00Z", "West coast"),
  ];

  it("picks the newest record for the team", () => {
    expect(newestPit(entries, 1111)?.id).toBe("b");
    expect(newestPit(entries, 9999)).toBeNull();
  });

  it("is absent without a team or a record", () => {
    const { container, rerender } = render(
      <PitBar team={0} entries={entries} config={config} />,
    );
    expect(container.textContent).toBe("");
    rerender(<PitBar team={9999} entries={entries} config={config} />);
    expect(container.textContent).toBe("");
  });

  it("opens the answers in a sheet and Escape closes it", () => {
    render(<PitBar team={1111} entries={entries} config={config} />);
    fireEvent.click(
      screen.getByRole("button", { name: /Pit report, Team 1111/ }),
    );
    const dialog = screen.getByRole("dialog", {
      name: "Pit report, team 1111",
    });
    expect(dialog.textContent).toContain("Drivetrain");
    expect(dialog.textContent).toContain("Swerve");
    expect(dialog.textContent).not.toContain("Tank");
    fireEvent.keyDown(dialog, { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
  });
});

describe("AlertBanner", () => {
  const alert = {
    entryId: "e1",
    teamNumber: 1111,
    tbaMatchKey: "2027test_qm4",
    fieldCodes: ["drive"],
  };

  it("lists the flagged entries and dismisses them", () => {
    const onDismiss = vi.fn();
    render(
      <AlertBanner alerts={[alert]} config={config} onDismiss={onDismiss} />,
    );
    expect(screen.getByText(/1 entry may have inaccurate data/)).toBeTruthy();
    expect(screen.getByText("Team 1111, Q4: Drivetrain")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));
    expect(onDismiss).toHaveBeenCalledOnce();
  });

  it("is absent with no alerts", () => {
    const { container } = render(
      <AlertBanner alerts={[]} config={config} onDismiss={() => undefined} />,
    );
    expect(container.textContent).toBe("");
  });
});

describe("pre-event card", () => {
  const unplayed = [{ redScore: -1, blueScore: -1 }, {}];
  it("shows for an event with no played match and no entry", () => {
    expect(showPreEvent("2027test", unplayed, 0)).toBe(true);
    expect(showPreEvent("2027test", [], 0)).toBe(true);
  });

  it("hides once a match is played, an entry exists, or there is no event", () => {
    expect(showPreEvent("2027test", [{ redScore: 0, blueScore: 3 }], 0)).toBe(
      false,
    );
    expect(showPreEvent("2027test", unplayed, 1)).toBe(false);
    expect(showPreEvent("", unplayed, 0)).toBe(false);
  });

  it("links to the prescout list", () => {
    render(
      <MemoryRouter>
        <PreEventCard />
      </MemoryRouter>,
    );
    expect(
      screen
        .getByRole("link", { name: "Pre-scout a team" })
        .getAttribute("href"),
    ).toBe("/scout/prescout");
  });
});
