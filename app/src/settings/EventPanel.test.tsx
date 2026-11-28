// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { parseConfig } from "../scout/config";
import { EventPanel } from "./EventPanel";

const state = vi.hoisted(() => ({
  eventKey: "2027old",
  signedIn: true,
  setEventKey: vi.fn(),
  refreshSchedule: vi.fn(() => Promise.resolve()),
  enqueueWrite: vi.fn(() => Promise.resolve("id")),
}));

vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: state.signedIn ? "signed-in" : "signed-out" }),
}));
vi.mock("../outbox/outbox", () => ({
  enqueueWrite: state.enqueueWrite,
  dismissItem: () => undefined,
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({
    eventKey: state.eventKey,
    setEventKey: state.setEventKey,
    refreshSchedule: state.refreshSchedule,
    schedule: [],
    scheduleStatus: "none",
    scheduleFetchedAt: null,
    config: parseConfig({ revision: 3, sections: [] }),
  }),
}));

const day = (offset: number) => {
  const d = new Date();
  d.setDate(d.getDate() + offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
};
const listed = [
  {
    key: "2027near",
    name: "Near Regional",
    startDate: day(0),
    endDate: day(2),
    week: 0,
    eventType: 0,
  },
  {
    key: "2027old",
    name: "Old Regional",
    startDate: day(1),
    endDate: day(2),
    week: 1,
    eventType: 0,
  },
  {
    key: "2027far",
    name: "Far Regional",
    startDate: "2000-01-01",
    endDate: "2000-01-03",
    week: 5,
    eventType: 0,
  },
];
vi.mock("./useSeasonEvents", () => ({
  useSeasonEvents: () => ({ status: "ready", events: listed }),
  savedEventName: () => null,
}));

beforeEach(() => {
  state.eventKey = "2027old";
  state.signedIn = true;
  state.setEventKey.mockClear();
  state.refreshSchedule.mockClear();
  state.enqueueWrite.mockClear();
  setRoles(ready("strategy"));
});
afterEach(cleanup);

const open = () => {
  render(<EventPanel />);
  fireEvent.click(screen.getByRole("button", { name: "Change event" }));
};

describe("event picker", () => {
  it("lists nearby events, and a search or Show all reaches the rest", () => {
    open();
    expect(screen.getByText("Near Regional")).toBeTruthy();
    expect(screen.queryByText("Far Regional")).toBeNull();
    fireEvent.change(screen.getByRole("searchbox"), {
      target: { value: "far" },
    });
    expect(screen.getByText("Far Regional")).toBeTruthy();
    fireEvent.change(screen.getByRole("searchbox"), { target: { value: "" } });
    fireEvent.click(screen.getByLabelText("Show all events"));
    expect(screen.getByText("Far Regional")).toBeTruthy();
  });

  it("labels each event with its week and key", () => {
    open();
    expect(screen.getByText("Week 1, 2027near")).toBeTruthy();
  });

  it("closes without changing anything on Cancel", () => {
    open();
    fireEvent.click(screen.getByRole("button", { name: "Cancel" }));
    expect(state.setEventKey).not.toHaveBeenCalled();
    expect(screen.getByRole("button", { name: "Change event" })).toBeTruthy();
  });
});

describe("choosing an event", () => {
  it("sets the device event and the team event for a lead", () => {
    open();
    fireEvent.click(screen.getByRole("button", { name: /Near Regional/ }));
    expect(state.setEventKey).toHaveBeenCalledWith("2027near");
    expect(state.enqueueWrite).toHaveBeenCalledTimes(1);
    const [path, doc, label] = state.enqueueWrite.mock.calls[0] as unknown as [
      string,
      { eventKey: string; updatedAt: string },
      string,
    ];
    expect(path).toBe("appConfig/activeEvent");
    expect(doc.eventKey).toBe("2027near");
    expect(Number.isNaN(Date.parse(doc.updatedAt))).toBe(false);
    expect(label).toBe("Team event");
  });

  it("never writes the team event for a scout", () => {
    setRoles(ready("scouter"));
    open();
    fireEvent.click(screen.getByRole("button", { name: /Near Regional/ }));
    expect(state.setEventKey).toHaveBeenCalledWith("2027near");
    expect(state.enqueueWrite).not.toHaveBeenCalled();
  });

  it("never writes the team event while signed out", () => {
    state.signedIn = false;
    open();
    fireEvent.click(screen.getByRole("button", { name: /Near Regional/ }));
    expect(state.setEventKey).toHaveBeenCalledWith("2027near");
    expect(state.enqueueWrite).not.toHaveBeenCalled();
  });

  it("only refreshes when the event is already the current one", () => {
    open();
    fireEvent.click(screen.getByRole("button", { name: /Old Regional/ }));
    expect(state.refreshSchedule).toHaveBeenCalled();
    expect(state.setEventKey).not.toHaveBeenCalled();
    expect(state.enqueueWrite).not.toHaveBeenCalled();
  });

  it("takes a typed key through the same rules", () => {
    setRoles(ready("scouter"));
    render(<EventPanel />);
    fireEvent.click(screen.getByText("Enter an event key"));
    fireEvent.change(screen.getByLabelText("Event key"), {
      target: { value: " 2027typed " },
    });
    fireEvent.click(screen.getByRole("button", { name: "Use this event" }));
    expect(state.setEventKey).toHaveBeenCalledWith("2027typed");
    expect(state.enqueueWrite).not.toHaveBeenCalled();
  });

  it("says who a pick reaches", () => {
    render(<EventPanel />);
    expect(
      screen.getByText(/becomes the event on every signed-in device/),
    ).toBeTruthy();
    cleanup();
    setRoles(ready("scouter"));
    render(<EventPanel />);
    expect(screen.getByText(/Your pick here lasts until/)).toBeTruthy();
  });
});
