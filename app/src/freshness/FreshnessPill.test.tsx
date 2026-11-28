// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { noteClosed, noteSnapshot } from "../data/syncState";
import { FreshnessPill } from "./FreshnessPill";

const state = vi.hoisted(() => ({
  outbox: [] as { status: string }[],
  eventKey: "2027test",
  resend: vi.fn(),
  refresh: vi.fn(() => Promise.resolve()),
}));

vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../outbox/outbox", () => ({ resendNow: () => state.resend() }));
vi.mock("../data/refresh", () => ({
  refreshEventData: () => state.refresh(),
}));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({ eventKey: state.eventKey }),
}));
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    status: "ready",
    fetchedAt: new Date(Date.now() - 3 * 60_000).toISOString(),
  }),
}));
vi.mock("../match/useOutside", () => ({
  useEpa: () => ({ status: "failed", data: null }),
}));

beforeEach(() => {
  state.outbox = [];
  state.eventKey = "2027test";
  state.resend.mockClear();
  state.refresh.mockClear();
  noteClosed("entries");
  noteSnapshot("entries", false);
});
afterEach(cleanup);

const pill = () => screen.getByRole("button", { name: /^Data status/ });
const open = () => fireEvent.click(pill());

describe("FreshnessPill", () => {
  it("says the data is synced when nothing is waiting", () => {
    render(<FreshnessPill />);
    expect(pill().getAttribute("aria-label")).toBe(
      "Data status: Synced. Open details.",
    );
  });

  it("keeps the unsent count on the pill", () => {
    state.outbox = [{ status: "on-device" }, { status: "refused" }];
    render(<FreshnessPill />);
    expect(pill().getAttribute("aria-label")).toContain("2 unsent");
    expect(within(pill()).getByText("2")).toBeTruthy();
  });

  it("opens the sheet with the answer and every source", () => {
    state.outbox = [{ status: "sending" }];
    render(<FreshnessPill />);
    open();
    const sheet = screen.getByRole("dialog", {
      name: "Is my data up to date?",
    });
    expect(within(sheet).getByText(/^Not yet\. 1 entry/)).toBeTruthy();
    for (const name of [
      "Scouting entries",
      "Pit scouting",
      "Pick lists",
      "Event data (The Blue Alliance)",
      "Event data (Statbotics)",
    ]) {
      expect(within(sheet).getByText(name)).toBeTruthy();
    }
    expect(within(sheet).getByText("Updated 3 minutes ago")).toBeTruthy();
    expect(within(sheet).getByText("Could not load")).toBeTruthy();
  });

  it("resends the outbox on Sync now", () => {
    render(<FreshnessPill />);
    open();
    fireEvent.click(screen.getByRole("button", { name: "Sync now" }));
    expect(state.resend).toHaveBeenCalledTimes(1);
    expect(screen.getByText("Sending what is waiting.")).toBeTruthy();
  });

  it("refetches event data on Refresh event data", async () => {
    render(<FreshnessPill />);
    open();
    fireEvent.click(screen.getByRole("button", { name: "Refresh event data" }));
    await waitFor(() =>
      expect(screen.getByText("Event data refreshed.")).toBeTruthy(),
    );
    expect(state.refresh).toHaveBeenCalledTimes(1);
  });

  it("has no event to refresh when none is set", () => {
    state.eventKey = "";
    render(<FreshnessPill />);
    open();
    expect(
      (
        screen.getByRole("button", {
          name: "Refresh event data",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
    expect(screen.getByText("No event selected")).toBeTruthy();
  });

  it("closes on Escape and returns focus to the pill", () => {
    render(<FreshnessPill />);
    open();
    fireEvent.keyDown(screen.getByRole("dialog"), { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(document.activeElement).toBe(pill());
  });
});
