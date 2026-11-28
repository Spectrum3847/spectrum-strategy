// @vitest-environment jsdom
import { cleanup, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newSession, sessionJson } from "./model";

const state = vi.hoisted(() => ({
  local: [] as { key: string; record: { doc: unknown; queuedMs: number } }[],
  matches: [] as { key: string; red: number[]; blue: number[] }[],
  tba: "none" as string,
  roles: ["strategy"] as string[],
  seen: null as {
    red: number[];
    blue: number[];
    ours: string;
    practice: boolean;
    canMoveSides: boolean;
  } | null,
}));

vi.mock("../auth/rolesContext", () => ({
  useRoles: () => ({ status: "ready", roles: state.roles }),
}));
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027a",
    status: state.tba,
    matches: state.matches,
  }),
}));
vi.mock("./remote", () => ({
  useRemoteBoardById: () => ({ board: null, ready: true, failed: false }),
}));
vi.mock("./local", () => ({
  idKey: (id: string) => `id|${id}`,
  listLocal: async () => state.local,
}));
vi.mock("./PlanTab", () => ({
  Board: (props: NonNullable<typeof state.seen>) => {
    state.seen = props;
    return <p>The board</p>;
  },
}));

import { BoardRoute } from "./BoardRoute";

const held = (
  alliance: string,
  teamNumbers: number[],
  opponentTeams: number[] | undefined,
) => {
  const session = newSession({
    id: "p1",
    eventKey: "2027a",
    matchNumber: 12,
    alliance,
    teamNumbers,
    ...(opponentTeams && { opponentTeams }),
    fieldId: "f",
    author: { uid: "u1", displayName: "Lead A" },
    nowMs: 1,
  });
  return { key: "id|p1", record: { doc: sessionJson(session), queuedMs: 0 } };
};

const open = async () => {
  render(
    <MemoryRouter initialEntries={["/boards/p1"]}>
      <Routes>
        <Route path="/boards/:id" element={<BoardRoute />} />
      </Routes>
    </MemoryRouter>,
  );
  await screen.findByText("The board");
};

beforeEach(() => {
  state.local = [];
  state.matches = [];
  state.tba = "none";
  state.roles = ["strategy"];
  state.seen = null;
});
afterEach(cleanup);

describe("reopening a practice board", () => {
  it("keeps opponents on their own side", async () => {
    state.local = [held("Red", [1111, 2222, 4444, 5555], [4444, 5555])];
    await open();
    expect(state.seen).toMatchObject({
      red: [1111, 2222],
      blue: [4444, 5555],
      ours: "red",
    });
  });

  it("puts opponents on red when we are blue", async () => {
    state.local = [held("Blue", [1111, 4444], [4444])];
    await open();
    expect(state.seen).toMatchObject({
      red: [4444],
      blue: [1111],
      ours: "blue",
    });
  });

  it("puts every team on our side for a board with no opponents", async () => {
    state.local = [held("Red", [1111, 2222], undefined)];
    await open();
    expect(state.seen).toMatchObject({ red: [1111, 2222], blue: [] });
  });

  it("still takes the sides of a scheduled match from the schedule", async () => {
    state.matches = [{ key: "2027a_qm12", red: [7777], blue: [8888] }];
    state.local = [held("Red", [1111, 4444], [4444])];
    await open();
    await waitFor(() =>
      expect(state.seen).toMatchObject({ red: [7777], blue: [8888] }),
    );
  });
});

describe("moving a team to the other side", () => {
  it("is offered to a lead on a practice board", async () => {
    state.local = [held("Red", [1111, 4444], [4444])];
    await open();
    expect(state.seen).toMatchObject({ practice: true, canMoveSides: true });
  });

  it("is offered on a board with no opponents once the schedule is known", async () => {
    state.local = [held("Red", [1111, 2222], undefined)];
    state.tba = "ready";
    await open();
    expect(state.seen).toMatchObject({ practice: true, canMoveSides: true });
  });

  it("waits for the schedule before treating a board with no opponents as practice", async () => {
    state.local = [held("Red", [1111, 2222], undefined)];
    await open();
    expect(state.seen).toMatchObject({ practice: false });
  });

  it("is not offered on a scheduled match", async () => {
    state.matches = [{ key: "2027a_qm12", red: [7777], blue: [8888] }];
    state.local = [held("Red", [1111, 4444], [4444])];
    await open();
    await waitFor(() =>
      expect(state.seen).toMatchObject({
        red: [7777],
        practice: false,
        canMoveSides: true,
      }),
    );
  });

  it("is not offered to a mentor", async () => {
    state.roles = ["mentor"];
    state.local = [held("Red", [1111, 4444], [4444])];
    await open();
    expect(state.seen).toMatchObject({ practice: true, canMoveSides: false });
  });
});
