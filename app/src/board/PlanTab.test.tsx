// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BoardController } from "./controller";
import { newSession } from "./model";
import PlanTab, { Board, type PlanProps } from "./PlanTab";

const held = vi.hoisted(() => ({ controller: null as BoardController | null }));

const exporter = vi.hoisted(() => ({ exportBoard: vi.fn() }));
vi.mock("./exportImage", async (original) => ({
  ...(await original<typeof import("./exportImage")>()),
  exportBoard: exporter.exportBoard,
}));

vi.mock("./useBoard", async () => {
  const { useMemo, useSyncExternalStore } = await import("react");
  const { BoardController: Controller } = await import("./controller");
  const { deliveryState } = await import("./sync");
  return {
    useBoard: (args: {
      eventKey: string;
      matchNumber: number;
      alliance: "Red" | "Blue";
      robots: { team: number; side: "red" | "blue" }[];
      practice?: boolean;
    }) => {
      const controller = useMemo(() => {
        const c = new Controller(
          {
            load: async () => null,
            save: async () => undefined,
            enqueue: async () => undefined,
            unsent: () => false,
            discard: () => undefined,
            now: Date.now,
            newId: () => "board-1",
            debounceMs: 1000,
          },
          { ...args, fieldId: "2026-rebuilt" },
        );
        c.setAuthor({ uid: "u1", displayName: "Lead A" });
        c.setRemote(null, true, false);
        void c.start();
        c.setPractice(args.practice === true);
        held.controller = c;
        return c;
      }, [args.eventKey, args.matchNumber]);
      const state = useSyncExternalStore(
        controller.subscribe,
        controller.getSnapshot,
      );
      return {
        controller,
        state,
        delivery: deliveryState({
          hasBoard: state.hasBoard,
          local: state.local,
          handed: state.handed,
          signedIn: true,
          item: undefined,
          remote: state.remote,
        }),
        online: true,
        failed: false,
      };
    },
  };
});

const props: PlanProps = {
  eventKey: "2027test",
  matchKey: "2027test_qm3",
  red: [1111, 2222, 3333],
  blue: [4444, 5555, 6666],
  ours: "red",
  label: "Q3",
};

const stage = { width: 800, height: 390 };

beforeEach(() => {
  Object.defineProperty(HTMLElement.prototype, "clientWidth", {
    configurable: true,
    get: () => stage.width,
  });
  Object.defineProperty(HTMLElement.prototype, "clientHeight", {
    configurable: true,
    get: () => stage.height,
  });
});
afterEach(() => {
  cleanup();
  held.controller = null;
});

async function board(over: Partial<PlanProps> = {}) {
  render(<PlanTab {...props} {...over} />);
  await screen.findByRole("group", { name: "Phase" });
}

const marker = (team: number) =>
  screen.queryByRole("button", { name: new RegExp(`^Team ${team}, `) });

describe("the board", () => {
  it("edits and moves a text label with the keyboard", async () => {
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Text" }));
    act(() => held.controller?.placeLabel({ x: 0.5, y: 0.5, text: "Defend" }));
    const label = screen.getByRole("button", { name: /^Defend\./ });
    fireEvent.keyDown(label, { key: "ArrowRight" });
    expect(held.controller?.getSnapshot().session.labels.auton[0]?.x).toBe(
      0.51,
    );
    fireEvent.keyDown(screen.getByRole("button", { name: /^Defend\./ }), {
      key: "Enter",
    });
    const input = screen.getByRole("textbox", { name: "Label text" });
    fireEvent.change(input, { target: { value: "Block" } });
    fireEvent.keyDown(input, { key: "Enter" });
    expect(screen.getByRole("button", { name: /^Block\./ })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Undo" }));
    expect(screen.getByRole("button", { name: /^Defend\./ })).toBeTruthy();
  });

  it("erases the label left in place after an earlier one is deleted", async () => {
    await board();
    const rect = vi
      .spyOn(HTMLElement.prototype, "getBoundingClientRect")
      .mockImplementation(function (this: HTMLElement) {
        return this.isConnected ? new DOMRect(0, 0, 400, 200) : new DOMRect();
      });
    act(() => {
      held.controller?.placeLabel({ x: 0.2, y: 0.2, text: "First" });
      held.controller?.placeLabel({ x: 0.6, y: 0.6, text: "Second" });
    });
    fireEvent.keyDown(screen.getByRole("button", { name: /^First\./ }), {
      key: "Delete",
    });
    fireEvent.click(screen.getByRole("button", { name: "Erase" }));
    const field = screen.getByRole("group", { name: /^Strategy board/ });
    fireEvent.pointerDown(field, { pointerId: 1, clientX: 10, clientY: 10 });
    fireEvent.pointerUp(field, { pointerId: 1, clientX: 10, clientY: 10 });
    expect(held.controller?.getSnapshot().session.labels.auton).toEqual([]);
    rect.mockRestore();
  });

  it("offers the phases, tools and undo, and names the phase for a screen reader", async () => {
    await board();
    expect(
      screen.getByRole("button", { name: "Auto", pressed: true }),
    ).toBeTruthy();
    for (const name of ["Teleop", "Endgame"]) {
      expect(screen.getByRole("button", { name, pressed: false })).toBeTruthy();
    }
    expect(
      screen.getByRole("button", { name: "Draw", pressed: true }),
    ).toBeTruthy();
    expect(screen.getByRole("button", { name: "Robot" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Erase" })).toBeTruthy();
    expect(
      screen.getByRole("button", { name: "Undo" }).hasAttribute("disabled"),
    ).toBe(true);
    expect(screen.getByText(/Draw: drag on the board/)).toBeTruthy();
    expect(
      screen.getByRole("group", { name: "Strategy board, Auto phase, empty" }),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Teleop" }));
    expect(
      screen.getByRole("group", {
        name: "Strategy board, Teleop phase, empty",
      }),
    ).toBeTruthy();
    expect(screen.getByLabelText("Notes for Teleop")).toBeTruthy();
  });

  it("lists the six robots when the Robot tool is on and places them all", async () => {
    await board();
    expect(screen.queryByRole("group", { name: "Robots" })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Robot" }));
    const tray = within(screen.getByRole("group", { name: "Robots" }));
    expect(tray.getAllByRole("button", { name: /^\d{4}, / })).toHaveLength(6);
    expect(
      tray.getByRole("button", { name: "1111, red", pressed: true }),
    ).toBeTruthy();
    fireEvent.click(tray.getByRole("button", { name: "Place all six" }));
    for (const team of [1111, 2222, 3333, 4444, 5555, 6666]) {
      expect(marker(team)).toBeTruthy();
    }
    expect(marker(4444)?.getAttribute("data-side")).toBe("blue");
    expect(
      tray.getByRole("button", { name: "1111, red, on the field" }),
    ).toBeTruthy();
    expect(
      screen.getByRole("group", {
        name: "Strategy board, Auto phase, 6 robots",
      }),
    ).toBeTruthy();
  });

  it("keeps each phase's robots apart and brings them back with undo", async () => {
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Robot" }));
    fireEvent.click(screen.getByRole("button", { name: "Place all six" }));
    fireEvent.click(screen.getByRole("button", { name: "Teleop" }));
    expect(marker(1111)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    fireEvent.click(screen.getByRole("button", { name: "Clear Auto" }));
    expect(marker(1111)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Undo" }));
    expect(marker(1111)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Redo" }));
    expect(marker(1111)).toBeNull();
  });

  it("clears every phase only after asking", async () => {
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Robot" }));
    fireEvent.click(screen.getByRole("button", { name: "Place all six" }));
    fireEvent.click(screen.getByRole("button", { name: "Teleop" }));
    fireEvent.click(screen.getByRole("button", { name: "Place all six" }));
    fireEvent.click(screen.getByRole("button", { name: "Clear all phases" }));
    const ask = within(screen.getByRole("alert"));
    fireEvent.click(ask.getByRole("button", { name: "Keep the board" }));
    expect(screen.queryByRole("alert")).toBeNull();
    expect(marker(1111)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Clear all phases" }));
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("alert")).toBeNull();
    expect(marker(1111)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Clear all phases" }));
    fireEvent.click(
      within(screen.getByRole("alert")).getByRole("button", {
        name: "Clear all phases",
      }),
    );
    expect(marker(1111)).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    expect(marker(1111)).toBeNull();
    expect(screen.queryByRole("alert")).toBeNull();
  });

  it("moves a robot with the arrow keys and removes it with Delete", async () => {
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Robot" }));
    fireEvent.click(screen.getByRole("button", { name: "Place all six" }));
    const before = held.controller?.getSnapshot().session.markers.auton[0];
    fireEvent.keyDown(marker(1111) as HTMLElement, { key: "ArrowRight" });
    const after = held.controller?.getSnapshot().session.markers.auton[0];
    expect(after?.position.x).toBeCloseTo((before?.position.x ?? 0) + 0.01, 5);
    fireEvent.keyDown(marker(1111) as HTMLElement, { key: "Delete" });
    expect(marker(1111)).toBeNull();
  });

  it("keeps a note per phase", async () => {
    await board();
    fireEvent.change(screen.getByLabelText("Notes for Auto"), {
      target: { value: "Cross to the left" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Teleop" }));
    expect(
      (screen.getByLabelText("Notes for Teleop") as HTMLTextAreaElement).value,
    ).toBe("");
    fireEvent.click(screen.getByRole("button", { name: "Auto" }));
    expect(
      (screen.getByLabelText("Notes for Auto") as HTMLTextAreaElement).value,
    ).toBe("Cross to the left");
  });

  it("says where a drawing is, never ahead of the facts", async () => {
    await board();
    expect(screen.getByText(/Nothing drawn yet/)).toBeTruthy();
    act(() =>
      held.controller?.commitStroke(
        [
          { x: 0.1, y: 0.1 },
          { x: 0.4, y: 0.4 },
        ],
        false,
      ),
    );
    expect(await screen.findByText("Saved on this device")).toBeTruthy();
    expect(screen.queryByText("In the database")).toBeNull();
  });

  it("offers the choice when another device saved a newer version", async () => {
    await board();
    act(() =>
      held.controller?.commitStroke(
        [
          { x: 0.1, y: 0.1 },
          { x: 0.4, y: 0.4 },
        ],
        false,
      ),
    );
    const theirs = newSession({
      id: "board-1",
      eventKey: "2027test",
      matchNumber: 3,
      alliance: "Red",
      teamNumbers: [],
      fieldId: "2026-rebuilt",
      author: { uid: "u2", displayName: "Lead B" },
      nowMs: Date.now() + 60_000,
    });
    act(() => held.controller?.setRemote(theirs, true, false));
    const alert = await screen.findByRole("alert");
    expect(
      within(alert).getByText(/Another device saved a newer version/),
    ).toBeTruthy();
    expect(within(alert).getByText(/Lead B saved it at/)).toBeTruthy();
    fireEvent.click(within(alert).getByRole("button", { name: "Keep mine" }));
    expect(
      screen.queryByText(/Another device saved a newer version/),
    ).toBeNull();
  });
});

describe("full screen", () => {
  it("opens as a dialog and closes with Escape", async () => {
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Full screen" }));
    const dialog = await screen.findByRole("dialog");
    expect(
      within(dialog).getByRole("button", { name: "Exit full screen" }),
    ).toBeTruthy();
    expect(within(dialog).queryByLabelText(/Notes for/)).toBeNull();
    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.getByRole("button", { name: "Full screen" })).toBeTruthy();
  });

  it("keeps the drawing when it opens", async () => {
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Robot" }));
    fireEvent.click(screen.getByRole("button", { name: "Place all six" }));
    fireEvent.click(screen.getByRole("button", { name: "Full screen" }));
    expect(await screen.findByRole("dialog")).toBeTruthy();
    expect(marker(1111)).toBeTruthy();
  });
});

describe("export image", () => {
  it("exports the current phase and says where it went", async () => {
    exporter.exportBoard.mockResolvedValue({
      delivery: "downloaded",
      fileName: "match_3_teleop.png",
    });
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Teleop" }));
    fireEvent.click(screen.getByRole("button", { name: "Export image" }));
    expect(
      await screen.findByText("Downloaded match_3_teleop.png."),
    ).toBeTruthy();
    expect(exporter.exportBoard.mock.calls[0]?.[0]).toMatchObject({
      phase: "teleop",
      title: "Match 3",
    });
  });

  it("says so when the image fails", async () => {
    exporter.exportBoard.mockRejectedValue(new Error("no canvas"));
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Export image" }));
    expect(
      await screen.findByText("Could not make the image. Try again."),
    ).toBeTruthy();
  });

  it("stays quiet when the share sheet is cancelled", async () => {
    exporter.exportBoard.mockResolvedValue({
      delivery: "cancelled",
      fileName: "x.png",
    });
    await board();
    fireEvent.click(screen.getByRole("button", { name: "Export image" }));
    await vi.waitFor(() =>
      expect(
        (
          screen.getByRole("button", {
            name: "Export image",
          }) as HTMLButtonElement
        ).disabled,
      ).toBe(false),
    );
    expect(screen.queryByText(/Shared|Downloaded|Could not make/)).toBeNull();
  });
});

describe("other matches", () => {
  it("has no board for a playoff match", () => {
    render(<PlanTab {...props} matchKey="2027test_sf2m1" />);
    expect(
      screen.getByText(/Boards are kept per qualification match number/),
    ).toBeTruthy();
  });

  it("asks for an event first", () => {
    render(<PlanTab {...props} eventKey="" />);
    expect(screen.getByText(/No event is set/)).toBeTruthy();
  });
});

describe("team sides", () => {
  const { matchKey: _matchKey, ...boardProps } = props;
  const practice = async (over: Partial<Parameters<typeof Board>[0]> = {}) => {
    render(
      <Board {...boardProps} matchNumber={3} practice canMoveSides {...over} />,
    );
    await screen.findByRole("group", { name: "Phase" });
  };

  it("moves a team to the other side with the keyboard and keeps the roster", async () => {
    await practice();
    const open = screen.getByRole("button", { name: "Team sides" });
    expect(open.getAttribute("aria-expanded")).toBe("false");
    fireEvent.click(open);
    expect(open.getAttribute("aria-expanded")).toBe("true");
    const move = screen.getByRole("button", { name: "Move 2222 to blue" });
    move.focus();
    fireEvent.click(move);
    expect(held.controller?.getSnapshot().session.opponentTeams).toEqual([
      2222, 4444, 5555, 6666,
    ]);
    const back = screen.getByRole("button", { name: "Move 2222 to red" });
    expect(document.activeElement).toBe(back);
    fireEvent.click(screen.getByRole("button", { name: "Robot" }));
    expect(screen.getByRole("button", { name: "2222, blue" })).toBeTruthy();
  });

  it("disables a move when the other side is full", async () => {
    await practice({ red: [1, 2, 3, 4, 5, 6], blue: [7, 8] });
    fireEvent.click(screen.getByRole("button", { name: "Team sides" }));
    expect(
      screen
        .getByRole("button", { name: "Move 7 to red" })
        .hasAttribute("disabled"),
    ).toBe(true);
    expect(
      screen
        .getByRole("button", { name: "Move 1 to blue" })
        .hasAttribute("disabled"),
    ).toBe(false);
  });

  it("is not offered on a scheduled board", async () => {
    await practice({ practice: false });
    expect(screen.queryByRole("button", { name: "Team sides" })).toBeNull();
  });

  it("is not offered to someone who cannot edit", async () => {
    await practice({ canMoveSides: false });
    expect(screen.queryByRole("button", { name: "Team sides" })).toBeNull();
  });
});
