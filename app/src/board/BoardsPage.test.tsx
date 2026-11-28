// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, type Session, sessionJson } from "./model";

const state = vi.hoisted(() => ({
  local: [] as { key: string; record: { doc: unknown; queuedMs: number } }[],
  remote: { boards: [] as unknown[], ready: true, failed: false },
  online: true,
  eventKey: "2027a",
  matches: [] as unknown[],
  deleted: [] as string[],
  removed: [] as string[],
  saved: [] as { key: string; record: { doc: Record<string, unknown> } }[],
  deleteFails: false,
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: "signed-in", uid: "u1", displayName: "Lead A" }),
}));
vi.mock("../auth/rolesContext", () => ({
  useRoles: () => ({
    status: "ready",
    roles: ["strategy"],
    displayName: "Lead A",
  }),
}));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({ eventKey: state.eventKey }),
}));
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({ matches: state.matches }),
}));
vi.mock("../ui/useOnline", () => ({ useOnline: () => state.online }));
vi.mock("../firebase/client", () => ({ db: {} }));
vi.mock("firebase/firestore", async (original) => ({
  ...(await original<typeof import("firebase/firestore")>()),
  doc: (_db: unknown, _c: string, id: string) => id,
  deleteDoc: (id: string) =>
    state.deleteFails
      ? Promise.reject(new Error("denied"))
      : Promise.resolve().then(() => {
          state.deleted.push(id);
          state.remote.boards = state.remote.boards.filter(
            (b) => (b as { id: string }).id !== id,
          );
        }),
}));
vi.mock("../outbox/outbox", () => ({
  getOutbox: () => [],
  dismissItem: () => undefined,
}));
vi.mock("./remote", () => ({ useRemoteBoards: () => state.remote }));
vi.mock("./local", () => ({
  idKey: (id: string) => `id|${id}`,
  listLocal: async () => state.local,
  deleteLocal: async (key: string) => {
    state.removed.push(key);
    state.local = state.local.filter((l) => l.key !== key);
  },
  saveLocal: async (key: string, record: { doc: Record<string, unknown> }) => {
    state.saved.push({ key, record });
  },
}));

import { Boards } from "./BoardsPage";

const make = (
  id: string,
  eventKey: string,
  ms: number,
  over = {},
): Session => ({
  ...newSession({
    id,
    eventKey,
    matchNumber: 7,
    alliance: "Red",
    teamNumbers: [],
    fieldId: "f",
    author: { uid: "u1", displayName: "Lead A" },
    nowMs: ms,
  }),
  ...over,
});
const held = (s: Session) => ({
  key: `id|${s.id}`,
  record: { doc: sessionJson(s), queuedMs: 0 },
});

function Where() {
  const { pathname } = useLocation();
  return <p data-testid="where">{pathname}</p>;
}

function view() {
  render(
    <MemoryRouter initialEntries={["/boards"]}>
      <Routes>
        <Route path="/boards" element={<Boards />} />
        <Route path="/boards/:id" element={<p>The board</p>} />
      </Routes>
      <Where />
    </MemoryRouter>,
  );
}

beforeEach(() => {
  state.local = [];
  state.remote = { boards: [], ready: true, failed: false };
  state.online = true;
  state.eventKey = "2027a";
  state.matches = [{ key: "2027a_qm5" }];
  state.deleted = [];
  state.removed = [];
  state.saved = [];
  state.deleteFails = false;
});
afterEach(cleanup);

describe("board list", () => {
  it("lists this device's boards and the team's boards apart", async () => {
    const mine = make("m1", "2027a", 20, { eventName: "Practice" });
    const theirs = make("t1", "2027a", 30, { authorDisplayName: "Lead B" });
    state.local = [held(mine)];
    state.remote = { boards: [mine, theirs], ready: true, failed: false };
    view();
    const device = await screen.findByRole("region", {
      name: "Boards on this device",
    });
    expect(within(device).getByText("Practice - Match 7")).toBeTruthy();
    const team = screen.getByRole("region", { name: "Team boards" });
    expect(within(team).getByText("Match 7")).toBeTruthy();
    expect(within(team).getByText(/by Lead B/)).toBeTruthy();
    expect(
      within(team).getByRole("link", { name: "Match 7" }).getAttribute("href"),
    ).toBe("/boards/t1");
  });

  it("filters to this event and says what is hidden", async () => {
    const other = make("o1", "2027b", 20);
    state.local = [held(other)];
    state.remote = { boards: [other], ready: true, failed: false };
    view();
    await screen.findByText(
      /No boards for this event yet. 1 from other events is hidden./,
    );
    const chip = screen.getByRole("button", { name: /This event only/ });
    expect(chip.getAttribute("aria-pressed")).toBe("true");
    fireEvent.click(chip);
    expect(await screen.findByText("Match 7")).toBeTruthy();
  });

  it("flags a device board the database does not have yet", async () => {
    state.local = [held(make("m1", "2027a", 20))];
    view();
    expect(await screen.findByText(/Not in the database yet/)).toBeTruthy();
  });

  it("says it is checking the database while the team's boards load", async () => {
    state.local = [held(make("m1", "2027a", 20))];
    state.remote = { boards: [], ready: false, failed: false };
    view();
    expect(await screen.findByText(/Checking the database/)).toBeTruthy();
    expect(screen.queryByText(/Not in the database yet/)).toBeNull();
  });

  it("deletes a board after asking, here and in the database", async () => {
    const mine = make("m1", "2027a", 20);
    state.local = [held(mine)];
    state.remote = { boards: [mine], ready: true, failed: false };
    view();
    fireEvent.click(
      await screen.findByRole("button", { name: "Delete Match 7" }),
    );
    fireEvent.click(screen.getByRole("button", { name: "Keep it" }));
    expect(state.deleted).toEqual([]);
    fireEvent.click(screen.getByRole("button", { name: "Delete Match 7" }));
    fireEvent.click(screen.getByRole("button", { name: "Delete board" }));
    await waitFor(() => expect(state.deleted).toEqual(["m1"]));
    await waitFor(() => expect(state.removed).toEqual(["id|m1"]));
    await screen.findByText(/No boards for this event yet|No boards yet/);
  });

  it("does not delete a device-only board from the database", async () => {
    state.local = [held(make("m1", "2027a", 20))];
    view();
    fireEvent.click(
      await screen.findByRole("button", { name: "Delete Match 7" }),
    );
    fireEvent.click(screen.getByRole("button", { name: "Delete board" }));
    await waitFor(() => expect(state.removed).toEqual(["id|m1"]));
    expect(state.deleted).toEqual([]);
  });

  it("keeps the board and says so when the delete is refused", async () => {
    const mine = make("m1", "2027a", 20);
    state.local = [held(mine)];
    state.remote = { boards: [mine], ready: true, failed: false };
    state.deleteFails = true;
    view();
    fireEvent.click(
      await screen.findByRole("button", { name: "Delete Match 7" }),
    );
    fireEvent.click(screen.getByRole("button", { name: "Delete board" }));
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /Could not delete the board/,
    );
    expect(state.removed).toEqual([]);
    expect(screen.getByText("Match 7")).toBeTruthy();
  });

  it("cannot delete while offline", async () => {
    state.online = false;
    state.local = [held(make("m1", "2027a", 20))];
    view();
    const button = await screen.findByRole("button", {
      name: "Delete Match 7",
    });
    expect((button as HTMLButtonElement).disabled).toBe(true);
    expect(screen.getByText(/Offline/)).toBeTruthy();
  });

  it("cannot delete until the team's boards have loaded", async () => {
    state.remote = { boards: [], ready: false, failed: false };
    state.local = [held(make("m1", "2027a", 20))];
    view();
    const button = await screen.findByRole("button", {
      name: "Delete Match 7",
    });
    expect((button as HTMLButtonElement).disabled).toBe(true);
  });

  it("shows no team boards section while the database has none", async () => {
    view();
    await screen.findByText(/No boards for this event yet|No boards yet/);
    expect(screen.queryByRole("region", { name: "Team boards" })).toBeNull();
  });
});

describe("new practice board", () => {
  const fill = (label: string | RegExp, value: string) =>
    fireEvent.change(screen.getByLabelText(label), { target: { value } });

  it("saves a board document on this device and opens it", async () => {
    view();
    fill("Match number", "12");
    fireEvent.change(screen.getByLabelText("Our alliance"), {
      target: { value: "Blue" },
    });
    fill("Name, optional", "Scrimmage");
    fill(/Our teams/, "3333, 1111");
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    await waitFor(() => expect(state.saved).toHaveLength(1));
    const saved = state.saved[0];
    expect(saved?.key).toMatch(/^id\|/);
    expect(saved?.record.doc).toMatchObject({
      eventKey: "2027a",
      eventName: "Scrimmage",
      matchNumber: 12,
      alliance: "Blue",
      teamNumbers: [1111, 3333],
      authorUid: "u1",
    });
    expect(saved?.record.doc).not.toHaveProperty("opponentTeams");
    await waitFor(() =>
      expect(screen.getByTestId("where").textContent).toMatch(/^\/boards\/.+/),
    );
  });

  it("records the opponent teams on the board document", async () => {
    view();
    fill("Match number", "12");
    fill(/Our teams/, "1111, 2222");
    fill(/Opponent teams/, "4444 3333");
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    await waitFor(() => expect(state.saved).toHaveLength(1));
    expect(state.saved[0]?.record.doc).toMatchObject({
      alliance: "Red",
      teamNumbers: [1111, 2222, 3333, 4444],
      opponentTeams: [3333, 4444],
    });
  });

  it("refuses a team typed on both sides", async () => {
    view();
    fill("Match number", "12");
    fill(/Our teams/, "1111, 2222");
    fill(/Opponent teams/, "2222, 3333");
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /On both sides: 2222/,
    );
    expect(state.saved).toHaveLength(0);
  });

  it("refuses a match number that is on the schedule", async () => {
    view();
    fill("Match number", "5");
    expect(
      screen.getByRole("link", { name: "Open its board" }).getAttribute("href"),
    ).toBe("/matches/2027a_qm5?tab=plan");
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /is on the schedule/,
    );
    expect(state.saved).toHaveLength(0);
  });

  it("checks the number and the teams", async () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /from 1 to 999/,
    );
    fill("Match number", "1000");
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /from 1 to 999/,
    );
    fill("Match number", "8");
    fill(/Our teams/, "abc");
    fireEvent.click(screen.getByRole("button", { name: "Create board" }));
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /Not a team number: abc/,
    );
    expect(state.saved).toHaveLength(0);
  });
});
