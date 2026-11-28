// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, describe, expect, it, vi } from "vitest";
import { parseShifts, parseTradeDocs, type ScoutShifts } from "../scout/credit";
import { ShiftsView, type ShiftsViewProps } from "./ShiftsView";

const grid = parseShifts({
  matchCount: 12,
  roster: [
    { uid: "u1", name: "Scout A" },
    { uid: "u2", name: "Scout B" },
    { uid: "", name: "Scout C" },
  ],
  rotations: [
    { uid: "u1", shifts: [{ startMatch: 1, endMatch: 6, station: "R1" }] },
    { uid: "u2", shifts: [{ startMatch: 7, endMatch: 12, station: "B2" }] },
    { uid: "", shifts: [] },
  ],
  cellOverrides: [{ col: 2, match: 3, text: "pit", color: "red" }],
}) as ScoutShifts;

const trade = (over: Record<string, unknown> = {}) => ({
  id: "t1",
  eventKey: "2027test",
  requesterUid: "u2",
  requesterDisplayName: "Scout B",
  targetUid: "u1",
  targetDisplayName: "Scout A",
  requesterBlock: { startMatch: 7, endMatch: 12 },
  status: "pending",
  createdAt: "2027-03-04T01:00:00.000Z",
  updatedAt: "2027-03-04T01:00:00.000Z",
  ...over,
});

function props(over: Partial<ShiftsViewProps> = {}): ShiftsViewProps {
  return {
    eventKey: "2027test",
    auth: "signed-in",
    uid: "u1",
    name: "Scout A",
    online: true,
    load: "ready",
    fromCache: false,
    shifts: grid,
    trades: [],
    played: 2,
    qualCount: 12,
    canEdit: false,
    deliveryOf: () => undefined,
    onDismiss: vi.fn(),
    onRequestTrade: vi.fn(),
    onAnswerTrade: vi.fn(),
    onSave: vi.fn(),
    onInputNames: vi.fn(),
    onRebuild: vi.fn(async () => null),
    notice: null,
    ...over,
  };
}

const view = (p: ShiftsViewProps) =>
  render(
    <MemoryRouter>
      <ShiftsView {...p} />
    </MemoryRouter>,
  );

afterEach(cleanup);

describe("read view", () => {
  it("shows my shifts first, then the grid with scouts by match", () => {
    view(props());
    const mine = screen.getByRole("region", { name: "My shifts" });
    expect(within(mine).getByText("Q1 to Q6")).toBeTruthy();
    expect(within(mine).getByText("R1")).toBeTruthy();
    expect(within(mine).getByText("On duty now")).toBeTruthy();
    const table = screen.getByRole("table", {
      name: "Scouting shifts by match",
    });
    expect(
      within(table)
        .getAllByRole("columnheader")
        .map((h) => h.textContent),
    ).toEqual(["Match", "Scout A", "Scout B", "Scout C"]);
    expect(within(table).getAllByRole("row")).toHaveLength(13);
    expect(within(table).getByText("pit")).toBeTruthy();
    expect(
      screen.getByRole("heading", { name: /Schedule, 12 qual matches/ }),
    ).toBeTruthy();
  });

  it("marks my column and shows nothing to press without edit rights", () => {
    view(props());
    expect(
      screen
        .getByRole("columnheader", { name: "Scout A" })
        .hasAttribute("data-mine"),
    ).toBe(true);
    expect(
      screen
        .getByRole("columnheader", { name: "Scout B" })
        .hasAttribute("data-mine"),
    ).toBe(false);
    expect(screen.queryByRole("button", { name: "Input names" })).toBeNull();
    expect(
      within(screen.getByRole("table")).queryAllByRole("button"),
    ).toHaveLength(0);
  });

  it("says when the account's own column is not linked", () => {
    view(props({ uid: "nobody", name: "scout c" }));
    expect(screen.getByText(/linked to your account/)).toBeTruthy();
  });

  it("says when the account is not on the grid at all", () => {
    view(props({ uid: "nobody", name: "Scout D" }));
    expect(screen.getByText("You are not on this schedule.")).toBeTruthy();
  });

  it("applies accepted trades to my shifts and the grid", () => {
    view(
      props({
        trades: parseTradeDocs([trade({ status: "accepted" })]),
      }),
    );
    const mine = screen.getByRole("region", { name: "My shifts" });
    expect(within(mine).getByText("Q7 to Q12")).toBeTruthy();
    expect(within(mine).getByText("Traded with Scout B")).toBeTruthy();
    expect(within(mine).getByText("B2")).toBeTruthy();
  });

  it("explains offline, a read failure, and no copy on the device", () => {
    view(props({ online: false, fromCache: true }));
    expect(screen.getByText(/Offline\. Showing the last copy/)).toBeTruthy();
    cleanup();
    view(props({ load: "failed", shifts: null }));
    expect(screen.getByRole("alert").textContent).toMatch(/could not be read/);
    cleanup();
    view(props({ online: false, fromCache: true, shifts: null }));
    expect(screen.getByText(/No copy of this event's shifts/)).toBeTruthy();
  });

  it("shows loading, empty, no event and signed-out states", () => {
    view(props({ load: "loading", shifts: null }));
    expect(screen.getByText("Loading the shifts.")).toBeTruthy();
    cleanup();
    view(props({ shifts: null }));
    expect(screen.getByText("Ask a strategy lead to build one.")).toBeTruthy();
    cleanup();
    view(props({ eventKey: "" }));
    expect(screen.getByText(/No event is selected/)).toBeTruthy();
    cleanup();
    view(props({ auth: "signed-out", uid: null }));
    expect(screen.getByText(/Sign in to see the shifts/)).toBeTruthy();
  });
});

describe("trades", () => {
  it("offers a block to a linked teammate", () => {
    const p = props();
    view(p);
    fireEvent.click(screen.getByRole("button", { name: "Trade this shift" }));
    const select = screen.getByLabelText("Ask who to cover Q1 to Q6?");
    expect(
      within(select)
        .getAllByRole("option")
        .map((o) => o.textContent),
    ).toEqual(["Pick a scout", "Scout B"]);
    const send = screen.getByRole("button", {
      name: "Send request",
    }) as HTMLButtonElement;
    expect(send.disabled).toBe(true);
    fireEvent.change(select, { target: { value: "u2" } });
    fireEvent.click(send);
    expect(p.onRequestTrade).toHaveBeenCalledWith(
      expect.objectContaining({ startMatch: 1, endMatch: 6 }),
      { uid: "u2", name: "Scout B" },
    );
  });

  it("lets the target take or decline an offered block", () => {
    const p = props({ trades: parseTradeDocs([trade()]) });
    view(p);
    expect(
      screen.getByText("Scout B asks you to cover Q7 to Q12."),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Take it" }));
    expect(p.onAnswerTrade).toHaveBeenCalledWith(p.trades[0], "accepted");
    fireEvent.click(screen.getByRole("button", { name: "Decline" }));
    expect(p.onAnswerTrade).toHaveBeenCalledWith(p.trades[0], "declined");
  });

  it("lets the requester cancel and hides the trade button meanwhile", () => {
    const p = props({
      trades: parseTradeDocs([
        trade({
          requesterUid: "u1",
          requesterDisplayName: "Scout A",
          targetUid: "u2",
          targetDisplayName: "Scout B",
          requesterBlock: { startMatch: 1, endMatch: 6 },
        }),
      ]),
    });
    view(p);
    expect(
      screen.getByText("You asked Scout B to cover Q1 to Q6."),
    ).toBeTruthy();
    expect(screen.getByText("Waiting for Scout B to answer")).toBeTruthy();
    expect(
      screen.queryByRole("button", { name: "Trade this shift" }),
    ).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Cancel request" }));
    expect(p.onAnswerTrade).toHaveBeenCalledWith(p.trades[0], "cancelled");
  });

  it("shows where each trade write stands, and a refusal with its reason", () => {
    const p = props({
      trades: parseTradeDocs([trade()]),
      deliveryOf: (path) =>
        path === "shiftTrades/t1"
          ? {
              id: "o1",
              status: "refused",
              error: "Missing or insufficient permissions.",
            }
          : undefined,
    });
    view(p);
    expect(screen.getByText("Refused")).toBeTruthy();
    expect(
      screen.getByText("Missing or insufficient permissions."),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));
    expect(p.onDismiss).toHaveBeenCalledWith("o1");
  });

  it("lists answered trades without buttons", () => {
    view(props({ trades: parseTradeDocs([trade({ status: "declined" })]) }));
    expect(
      screen.getByText("You declined Q7 to Q12 from Scout B."),
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Take it" })).toBeNull();
  });
});

describe("lead editing", () => {
  it("paints a tapped cell with the chosen color", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.click(screen.getByRole("button", { name: "Grey" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Scout B, match 2, off" }),
    );
    const next = (p.onSave as ReturnType<typeof vi.fn>).mock
      .calls[0]?.[0] as ScoutShifts;
    expect(next.colors.get("1:2")).toBe("grey");
    expect(next.colors.get("2:3")).toBe("red");
  });

  it("paints a range between two taps", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.click(screen.getByRole("button", { name: "Red" }));
    fireEvent.click(screen.getByRole("button", { name: "Range" }));
    fireEvent.click(
      screen.getByRole("button", { name: "Scout A, match 7, off" }),
    );
    expect(p.onSave).not.toHaveBeenCalled();
    fireEvent.click(
      screen.getByRole("button", { name: "Scout B, match 9, on duty, B2" }),
    );
    const next = (p.onSave as ReturnType<typeof vi.fn>).mock
      .calls[0]?.[0] as ScoutShifts;
    expect([...next.colors.keys()].sort()).toEqual(
      ["0:7", "0:8", "0:9", "1:7", "1:8", "1:9", "2:3"].sort(),
    );
  });

  it("types a note on a cell and clears it with empty text", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.click(screen.getByRole("button", { name: "Note" }));
    fireEvent.change(screen.getByLabelText(/Note text/), {
      target: { value: "  lunch " },
    });
    fireEvent.click(
      screen.getByRole("button", { name: "Scout A, match 9, off" }),
    );
    const next = (p.onSave as ReturnType<typeof vi.fn>).mock
      .calls[0]?.[0] as ScoutShifts;
    expect(next.texts.get("0:9")).toBe("lunch");
  });

  it("asks before replacing existing shifts, then generates", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.click(
      screen.getByRole("button", { name: "Generate scouting schedule" }),
    );
    expect(p.onSave).not.toHaveBeenCalled();
    expect(screen.getByText(/replaces everyone's shifts/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Replace shifts" }));
    const next = (p.onSave as ReturnType<typeof vi.fn>).mock
      .calls[0]?.[0] as ScoutShifts;
    expect(next.rotations[2]?.blocks).toEqual([
      { startMatch: 7, endMatch: 12, station: "R1" },
    ]);
    expect(next.rotations[0]?.blocks[0]?.station).toBe("R1");
  });

  it("generates at once on a grid with no shifts yet", () => {
    const blankGrid = parseShifts({
      matchCount: 6,
      roster: [{ uid: "u1", name: "Scout A" }],
    }) as ScoutShifts;
    const p = props({ canEdit: true, shifts: blankGrid });
    view(p);
    fireEvent.click(
      screen.getByRole("button", { name: "Generate scouting schedule" }),
    );
    const next = (p.onSave as ReturnType<typeof vi.fn>).mock
      .calls[0]?.[0] as ScoutShifts;
    expect(next.rotations[0]?.blocks).toEqual([
      { startMatch: 1, endMatch: 6, station: "R1" },
    ]);
  });

  it("sends the typed names and match count", () => {
    const p = props({ canEdit: true, shifts: null, qualCount: 0 });
    view(p);
    fireEvent.click(screen.getByRole("button", { name: "Input names" }));
    fireEvent.click(screen.getByRole("button", { name: "Save names" }));
    expect(screen.getByRole("alert").textContent).toMatch(/at least one name/);
    fireEvent.change(screen.getByLabelText("Scout names"), {
      target: { value: "Ada\nGrace, Ada" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save names" }));
    expect(screen.getByRole("alert").textContent).toMatch(
      /how many qualification/,
    );
    fireEvent.change(screen.getByLabelText("Qualification matches"), {
      target: { value: "1000" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save names" }));
    expect(screen.getByRole("alert").textContent).toMatch(/more than 999/);
    fireEvent.change(screen.getByLabelText("Qualification matches"), {
      target: { value: "80" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save names" }));
    expect(p.onInputNames).toHaveBeenCalledWith(["Ada", "Grace"], 80);
  });

  it("starts the match count from the event's qualification matches", () => {
    view(props({ canEdit: true, shifts: null, qualCount: 64 }));
    fireEvent.click(screen.getByRole("button", { name: "Input names" }));
    expect(
      (screen.getByLabelText("Qualification matches") as HTMLInputElement)
        .value,
    ).toBe("64");
  });

  it("says Replace grid when a roster already exists", () => {
    view(props({ canEdit: true }));
    fireEvent.click(screen.getByRole("button", { name: "Input names" }));
    expect(screen.getByRole("button", { name: "Replace grid" })).toBeTruthy();
    expect(
      (screen.getByLabelText("Scout names") as HTMLTextAreaElement).value,
    ).toBe("Scout A\nScout B\nScout C");
  });

  it("shows where the grid save stands", () => {
    view(
      props({
        canEdit: true,
        deliveryOf: (path) =>
          path === "scoutShifts/2027test"
            ? { id: "o2", status: "sending" }
            : undefined,
      }),
    );
    expect(screen.getByText("Sending")).toBeTruthy();
  });

  it("shows a notice from the container", () => {
    view(props({ canEdit: true, notice: "No matching account: Zed." }));
    expect(screen.getByText("No matching account: Zed.")).toBeTruthy();
  });
});

describe("mid-event changes", () => {
  const saved = (p: ShiftsViewProps) =>
    (p.onSave as ReturnType<typeof vi.fn>).mock.calls[0]?.[0] as ScoutShifts;

  it("is hidden without edit rights", () => {
    view(props());
    expect(screen.queryByText("Mid-event changes")).toBeNull();
  });

  it("marks a scout unavailable for a range and says so", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.change(screen.getByLabelText("Scout"), {
      target: { value: "1" },
    });
    fireEvent.change(screen.getByLabelText("From match"), {
      target: { value: "3" },
    });
    fireEvent.change(screen.getByLabelText("To match"), {
      target: { value: "4" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Mark unavailable" }));
    expect(saved(p).colors.get("1:3")).toBe("red");
    expect(saved(p).colors.get("1:4")).toBe("red");
    expect(saved(p).colors.get("1:5")).toBeUndefined();
    expect(
      screen.getByText("Scout B is unavailable for Q3 to Q4."),
    ).toBeTruthy();
  });

  it("takes a single match and refuses a bad range", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.click(screen.getByRole("button", { name: "Mark unavailable" }));
    expect(screen.getByRole("alert").textContent).toMatch(/from 1 to 12/);
    expect(p.onSave).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText("From match"), {
      target: { value: "5" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Mark unavailable" }));
    expect(saved(p).colors.get("0:5")).toBe("red");
  });

  it("clears unavailable marks in a range", () => {
    const p = props({ canEdit: true });
    view(p);
    fireEvent.change(screen.getByLabelText("Scout"), {
      target: { value: "2" },
    });
    fireEvent.change(screen.getByLabelText("From match"), {
      target: { value: "1" },
    });
    fireEvent.change(screen.getByLabelText("To match"), {
      target: { value: "6" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Clear unavailable" }));
    expect(saved(p).colors.has("2:3")).toBe(false);
  });

  it("starts the rebuild at the next block after the last played match", () => {
    view(props({ canEdit: true, played: 8 }));
    expect(
      (screen.getByLabelText("Rebuild from match") as HTMLInputElement).value,
    ).toBe("13");
  });

  it("asks before rebuilding, then rebuilds and shows what changed", async () => {
    const p = props({
      canEdit: true,
      played: 6,
      onRebuild: vi.fn(async () => ({
        from: 7,
        keptShifts: 1,
        newShifts: 6,
        changed: ["Scout B"],
        warnings: ["Q7 to Q12: 5 of 6 stations have no scout."],
      })),
    });
    view(p);
    fireEvent.change(screen.getByLabelText(/Add scouts/), {
      target: { value: "Dana\nEli" },
    });
    fireEvent.click(
      screen.getByRole("button", { name: "Rebuild from next shift" }),
    );
    expect(p.onRebuild).not.toHaveBeenCalled();
    expect(
      screen.getByText(/Keeps every shift that started before Q7/).textContent,
    ).toMatch(/Adds 2 scouts\. Red cells and notes stay\./);
    fireEvent.click(screen.getByRole("button", { name: "Replace the rest" }));
    expect(p.onRebuild).toHaveBeenCalledWith(7, ["Dana", "Eli"]);
    expect(await screen.findByText(/Rebuilt from Q7/)).toBeTruthy();
    expect(
      screen.getByText(/1 scout has different shifts: Scout B/),
    ).toBeTruthy();
    expect(screen.getByText(/5 of 6 stations have no scout/)).toBeTruthy();
  });

  it("backs out of a rebuild and refuses a match outside the event", () => {
    const p = props({ canEdit: true, played: 6 });
    view(p);
    fireEvent.click(
      screen.getByRole("button", { name: "Rebuild from next shift" }),
    );
    fireEvent.click(
      screen.getByRole("button", { name: "Keep current shifts" }),
    );
    expect(p.onRebuild).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText("Rebuild from match"), {
      target: { value: "13" },
    });
    fireEvent.click(
      screen.getByRole("button", { name: "Rebuild from next shift" }),
    );
    expect(screen.getByRole("alert").textContent).toMatch(/from 1 to 12/);
    expect(p.onRebuild).not.toHaveBeenCalled();
  });

  it("offers only the unavailable marks before a schedule exists", () => {
    const blankGrid = parseShifts({
      matchCount: 6,
      roster: [{ uid: "u1", name: "Scout A" }],
    }) as ScoutShifts;
    view(props({ canEdit: true, shifts: blankGrid }));
    expect(screen.getByLabelText("From match")).toBeTruthy();
    expect(screen.queryByLabelText("Rebuild from match")).toBeNull();
  });
});
