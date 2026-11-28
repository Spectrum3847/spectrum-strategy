// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { ready, setRoles } from "../auth/rolesMock";
import type { EventEntry } from "../data/parse";
import { parseConfig } from "../scout/config";
import { Database } from "./DatabasePage";

const config = parseConfig(bundled);

const state = vi.hoisted(() => ({
  entries: [] as unknown[],
  corrections: [] as unknown[],
  pit: [] as unknown[],
  failed: false,
  saveCorrection: vi.fn((..._args: unknown[]) => Promise.resolve()),
  deleted: vi.fn((..._args: unknown[]) => Promise.resolve("o1")),
  all: [] as unknown[],
  refresh: vi.fn((..._args: unknown[]) => Promise.resolve()),
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: "signed-in",
    uid: "u1",
    displayName: "Lead A",
  }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({ config, eventKey: "2027test", schedule: [] }),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({
    items: state.entries,
    ready: true,
    failed: state.failed,
  }),
}));
vi.mock("../data/useCorrections", () => ({
  useCorrections: () => ({
    items: state.corrections,
    ready: true,
    failed: false,
  }),
  saveCorrection: (...args: unknown[]) => state.saveCorrection(...args),
}));
vi.mock("../data/useCollections", async () => {
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const { parseConfig: parse } = await import("../scout/config");
  return {
    usePitEntries: () => ({ items: state.pit, ready: true, failed: false }),
    usePrescoutEntries: () => ({ items: [], ready: true, failed: false }),
    useFormConfig: () => parse(pit.default),
  };
});
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../outbox/outbox", () => ({
  enqueueDelete: (...args: unknown[]) => state.deleted(...args),
  getOutbox: () => [],
  subscribeOutbox: () => () => undefined,
}));
vi.mock("../photos/service", () => import("../photos/fakeService"));
vi.mock("./useAllEntries", () => ({
  seasonOf: (key: string) => /^\d{4}/.exec(key)?.[0] ?? null,
  useAllEntries: (enabled: boolean) => ({
    items: enabled ? state.all : [],
    ready: true,
    failed: false,
  }),
}));
vi.mock("./refresh", () => ({
  refreshFromServer: (...args: unknown[]) => state.refresh(...args),
}));

const entry = (
  id: string,
  key: string,
  team: number,
  scout: string,
  values: Record<string, unknown> = {},
): EventEntry => ({
  id,
  teamNumber: team,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: scout,
  authorUid: "u9",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

const setWidth = (width: number) => {
  Object.defineProperty(window, "innerWidth", {
    value: width,
    configurable: true,
  });
  window.dispatchEvent(new Event("resize"));
};

const setOnline = (online: boolean) => {
  Object.defineProperty(navigator, "onLine", {
    value: online,
    configurable: true,
  });
  window.dispatchEvent(new Event(online ? "online" : "offline"));
};

const view = () =>
  render(
    <MemoryRouter>
      <Database />
    </MemoryRouter>,
  );

beforeEach(() => {
  state.entries = [
    entry("a", "2027test_qm1", 1111, "Scout A", {
      robot: "R1",
      teleopFuelScored: 10,
    }),
    entry("b", "2027test_qm2", 2222, "Scout B", { teleopFuelScored: 4 }),
  ];
  state.corrections = [];
  state.pit = [];
  state.failed = false;
  state.saveCorrection.mockClear();
  state.deleted.mockClear();
  state.refresh.mockClear();
  state.all = [];
  setOnline(true);
  setRoles(ready("strategy"));
  setWidth(1024);
  window.scrollTo = () => undefined;
});
afterEach(cleanup);

const tableEl = () => document.querySelector("table") as HTMLElement;
const bodyRows = () => within(tableEl()).getAllByRole("row").slice(1);

describe("database page", () => {
  it("lists every entry with a linked match and team", () => {
    view();
    expect(screen.getByRole("heading", { name: "Database" })).toBeTruthy();
    expect(bodyRows()).toHaveLength(2);
    expect(screen.getByRole("link", { name: "Q1" }).getAttribute("href")).toBe(
      "/matches/2027test_qm1",
    );
    expect(
      screen.getByRole("link", { name: "1111" }).getAttribute("href"),
    ).toBe("/teams/1111");
    expect(screen.getByText("2 entries.")).toBeTruthy();
  });

  it("shows a cards and deaths column only when an entry has one", () => {
    view();
    expect(
      screen.queryByRole("columnheader", { name: "Cards and deaths" }),
    ).toBeNull();
    cleanup();
    state.entries = [
      entry("a", "2027test_qm1", 1111, "Scout A", { ryCard: "Yellow" }),
      entry("b", "2027test_qm2", 2222, "Scout B"),
    ];
    view();
    expect(
      screen.getByRole("columnheader", { name: "Cards and deaths" }),
    ).toBeTruthy();
    expect(screen.getByText("Yellow card")).toBeTruthy();
  });

  it("sorts by team when the heading is pressed, and again to reverse", () => {
    view();
    const first = () =>
      within(bodyRows()[0] as HTMLElement).getAllByRole("link")[0]?.textContent;
    expect(first()).toBe("1111");
    fireEvent.click(screen.getByRole("button", { name: "Team" }));
    fireEvent.click(screen.getByRole("button", { name: "Team" }));
    expect(
      within(bodyRows()[0] as HTMLElement).getAllByRole("link")[0]?.textContent,
    ).toBe("2222");
  });

  it("filters by team, scout and match range", () => {
    view();
    fireEvent.change(screen.getByLabelText("Team"), {
      target: { value: "22" },
    });
    expect(bodyRows()).toHaveLength(1);
    expect(screen.getByText("1 of 2 entries.")).toBeTruthy();
    fireEvent.change(screen.getByLabelText("Team"), { target: { value: "" } });
    fireEvent.change(screen.getByLabelText("Scout"), {
      target: { value: "Scout A" },
    });
    expect(bodyRows()).toHaveLength(1);
    fireEvent.change(screen.getByLabelText("Scout"), { target: { value: "" } });
    fireEvent.change(screen.getByLabelText("From match"), {
      target: { value: "2" },
    });
    expect(bodyRows()).toHaveLength(1);
    fireEvent.change(screen.getByLabelText("To match"), {
      target: { value: "1" },
    });
    expect(screen.getByText("No entry matches these filters.")).toBeTruthy();
  });

  it("pages a large event", () => {
    state.entries = Array.from({ length: 230 }, (_, i) =>
      entry(`e${i}`, `2027test_qm${i + 1}`, 1000 + i, "Scout A"),
    );
    view();
    expect(bodyRows()).toHaveLength(100);
    fireEvent.click(screen.getByRole("button", { name: "Show 100 more" }));
    expect(bodyRows()).toHaveLength(200);
    fireEvent.click(screen.getByRole("button", { name: "Show 30 more" }));
    expect(bodyRows()).toHaveLength(230);
  });

  it("marks a corrected value and what the scout entered", () => {
    state.corrections = [
      {
        id: "a",
        eventKey: "2027test",
        fields: { teleopFuelScored: 30 },
        note: "",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        history: [],
        updatedMs: 1,
      },
    ];
    view();
    expect(screen.getByText("Scout entered 10")).toBeTruthy();
  });

  it("opens the correction editor from a row and saves", async () => {
    view();
    fireEvent.click(
      screen.getByRole("button", { name: "Form for team 1111, Q1" }),
    );
    expect(
      screen.getByRole("heading", { name: "Correct team 1111, Q1" }),
    ).toBeTruthy();
    const teleop = within(screen.getByRole("group", { name: "Teleop" }));
    fireEvent.click(teleop.getByRole("button", { name: "Fuel Scored plus 5" }));
    fireEvent.click(screen.getByRole("button", { name: "Save correction" }));
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(1));
    expect(state.saveCorrection.mock.calls[0]?.[0]).toMatchObject({
      id: "a",
      fields: { teleopFuelScored: 15 },
      authorUid: "u1",
    });
    expect(state.saveCorrection.mock.calls[0]?.[1]).toBe(
      "Correction for team 1111, Q1",
    );
    await screen.findByText("Correction saved on this device.");
    fireEvent.click(
      screen.getByRole("button", { name: "Back to the database" }),
    );
    expect(bodyRows()).toHaveLength(2);
  });

  it("keeps the filters after an edit", () => {
    view();
    fireEvent.change(screen.getByLabelText("Team"), {
      target: { value: "22" },
    });
    fireEvent.click(
      screen.getByRole("button", { name: "Form for team 2222, Q2" }),
    );
    fireEvent.click(
      screen.getByRole("button", { name: "Back to the database" }),
    );
    expect((screen.getByLabelText("Team") as HTMLInputElement).value).toBe(
      "22",
    );
    expect(bodyRows()).toHaveLength(1);
  });

  it("gives a scouter no way in to Correct", () => {
    setRoles(ready("scouter"));
    view();
    expect(screen.queryByRole("button", { name: /^Form for/ })).toBeNull();
  });

  it("stacks entries as a list on a phone", () => {
    setWidth(400);
    view();
    expect(document.querySelector("table")).toBeNull();
    const items = screen.getAllByRole("listitem");
    expect(items).toHaveLength(2);
    expect(within(items[0] as HTMLElement).getByText("Scout A")).toBeTruthy();
    const details = (items[0] as HTMLElement).querySelector(
      "details",
    ) as HTMLDetailsElement;
    details.open = true;
    fireEvent(details, new Event("toggle"));
    expect(within(items[0] as HTMLElement).getByText("10")).toBeTruthy();
    expect(
      within(items[0] as HTMLElement).getByRole("button", {
        name: /^Form for/,
      }),
    ).toBeTruthy();
  });

  it("says so when there are no entries, and when loading failed", () => {
    state.entries = [];
    state.failed = true;
    view();
    expect(screen.getByText("No scout entries for 2027test yet.")).toBeTruthy();
    expect(screen.getByRole("alert").textContent).toMatch(/incomplete/);
  });

  it("shows pit records read only", () => {
    state.pit = [
      {
        id: "p",
        teamNumber: 3333,
        eventKey: "2027test",
        fieldValues: {},
        authorUid: "u",
        scoutName: "Scout C",
        updatedAt: "2027-03-01T10:00:00.000Z",
        photoKeys: [],
      },
    ];
    view();
    fireEvent.click(screen.getByRole("button", { name: "Pit" }));
    expect(bodyRows()).toHaveLength(1);
    expect(
      within(bodyRows()[0] as HTMLElement).getByText("Scout C"),
    ).toBeTruthy();
    expect(screen.queryByRole("button", { name: /^Form for/ })).toBeNull();
  });
});

describe("deleting entries", () => {
  const rowOne = () => bodyRows()[0] as HTMLElement;

  it("asks first, then sends the delete through the outbox", async () => {
    view();
    fireEvent.click(
      within(rowOne()).getByRole("button", { name: /^Delete team 1111/ }),
    );
    expect(state.deleted).not.toHaveBeenCalled();
    fireEvent.click(
      within(rowOne()).getByRole("button", { name: /^Confirm delete/ }),
    );
    await waitFor(() =>
      expect(state.deleted).toHaveBeenCalledWith(
        "scoutEntries/a",
        expect.stringContaining("1111"),
      ),
    );
  });

  it("offers a scouter only their own entries", () => {
    setRoles(ready("scouter"));
    state.entries = [
      entry("a", "2027test_qm1", 1111, "Scout A"),
      { ...entry("b", "2027test_qm2", 2222, "Scout B"), authorUid: "u1" },
    ];
    view();
    expect(
      screen.getAllByRole("button", { name: /^Delete team/ }),
    ).toHaveLength(1);
    expect(
      screen.getByRole("button", { name: /^Delete team 2222/ }),
    ).toBeTruthy();
  });

  it("offers a mentor no delete", () => {
    setRoles(ready("mentor"));
    view();
    expect(screen.queryByRole("button", { name: /^Delete/ })).toBeNull();
  });

  it("deletes a pit record by its path", async () => {
    state.pit = [
      {
        id: "p",
        teamNumber: 3333,
        eventKey: "2027test",
        fieldValues: {},
        authorUid: "u",
        scoutName: "Scout C",
        updatedAt: "2027-03-01T10:00:00.000Z",
        photoKeys: [],
      },
    ];
    view();
    fireEvent.click(screen.getByRole("button", { name: "Pit" }));
    fireEvent.click(screen.getByRole("button", { name: /^Delete team 3333/ }));
    fireEvent.click(screen.getByRole("button", { name: /^Confirm delete/ }));
    await waitFor(() =>
      expect(state.deleted).toHaveBeenCalledWith(
        "pitScoutEntries/p",
        expect.stringContaining("3333"),
      ),
    );
  });
});

describe("database page tools", () => {
  it("marks two rows on one team in a match and adds the Check column", () => {
    state.entries = [
      entry("a", "2027test_qm1", 1111, "Scout A"),
      entry("b", "2027test_qm1", 1111, "Scout B"),
      entry("c", "2027test_qm2", 2222, "Scout C"),
    ];
    view();
    expect(screen.getByRole("columnheader", { name: "Check" })).toBeTruthy();
    const rows = bodyRows();
    expect(within(rows[0] as HTMLElement).getByText(/Same team/)).toBeTruthy();
    expect(within(rows[1] as HTMLElement).getByText(/Same team/)).toBeTruthy();
    expect(within(rows[2] as HTMLElement).queryByText(/Same team/)).toBeNull();
  });

  it("adds no Check column when nothing is wrong", () => {
    view();
    expect(screen.queryByRole("columnheader", { name: "Check" })).toBeNull();
  });

  it("shows every event's entries and stops offering Correct", () => {
    state.all = [
      entry("a", "2027test_qm1", 1111, "Scout A"),
      entry("z", "2027other_qm1", 9999, "Scout Z"),
      entry("y", "2027other_qm2", 9998, "Scout Y"),
    ];
    view();
    expect(bodyRows()).toHaveLength(2);
    fireEvent.click(screen.getByRole("button", { name: "All 2027 events" }));
    expect(bodyRows()).toHaveLength(3);
    expect(screen.queryByRole("button", { name: /^Form for/ })).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "This event" }));
    expect(bodyRows()).toHaveLength(2);
    expect(screen.getAllByRole("button", { name: /^Form for/ })).toHaveLength(
      2,
    );
  });

  it("refreshes from the database for the scope on screen", async () => {
    view();
    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));
    await waitFor(() =>
      expect(screen.getByText("Up to date with the database.")).toBeTruthy(),
    );
    expect(state.refresh).toHaveBeenCalledWith("match", "2027test", false);
    fireEvent.click(screen.getByRole("button", { name: "All 2027 events" }));
    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));
    await waitFor(() =>
      expect(state.refresh).toHaveBeenLastCalledWith("match", "2027test", true),
    );
  });

  it("says so when the refresh cannot reach the database", async () => {
    state.refresh.mockRejectedValueOnce(new Error("offline"));
    view();
    fireEvent.click(screen.getByRole("button", { name: "Refresh" }));
    expect(
      await screen.findByText(/Could not reach the database/),
    ).toBeTruthy();
  });

  it("says it is showing cached entries when offline", () => {
    setOnline(false);
    view();
    expect(
      screen.getByText(/Offline\. Showing the entries saved/),
    ).toBeTruthy();
    expect(
      (screen.getByRole("button", { name: "Refresh" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
  });

  it("links leads to Scout accuracy and nobody else", () => {
    view();
    expect(
      screen.getByRole("link", { name: "Scout accuracy" }).getAttribute("href"),
    ).toBe("/scout/accuracy");
    cleanup();
    setRoles(ready("mentor"));
    view();
    expect(screen.queryByRole("link", { name: "Scout accuracy" })).toBeNull();
  });
});

const tree = () => (
  <MemoryRouter>
    <Database />
  </MemoryRouter>
);

describe("editing cells in place", () => {
  const headers = () =>
    Array.from(tableEl().querySelectorAll("thead th")).map(
      (h) => h.textContent ?? "",
    );
  const cell = (row: number, title: string, nth = 0) => {
    const index = headers()
      .map((h, i) => [h, i] as const)
      .filter(([h]) => h === title)[nth]?.[1];
    if (index === undefined) throw new Error(`no column ${title}`);
    return (bodyRows()[row] as HTMLTableRowElement).cells[index] as HTMLElement;
  };
  const teleop = (row = 0) => cell(row, "Fuel Scored", 1);
  const saved = (n: number) =>
    state.saveCorrection.mock.calls[n]?.[0] as {
      fields: Record<string, unknown>;
      history: Record<string, unknown>[];
    };
  const type = (value: string) =>
    fireEvent.change(screen.getByRole("textbox", { name: "Fuel Scored" }), {
      target: { value },
    });

  it("opens a cell on click, saves on Enter and moves down", async () => {
    view();
    fireEvent.click(teleop());
    type("12");
    fireEvent.keyDown(teleop(), { key: "Enter" });
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(1));
    expect(saved(0).fields).toEqual({ teleopFuelScored: 12 });
    expect(saved(0).history[0]).toMatchObject({
      field: "teleopFuelScored",
      from: 10,
      to: 12,
      how: "table",
      by: "Scout A",
    });
    expect(state.saveCorrection.mock.calls[0]?.[1]).toBe(
      "Correction for team 1111, Q1",
    );
    expect(screen.queryByRole("textbox", { name: "Fuel Scored" })).toBeNull();
    await waitFor(() => expect(document.activeElement).toBe(teleop(1)));
  });

  it("saves on Tab and moves right", async () => {
    view();
    fireEvent.click(teleop());
    type("11");
    fireEvent.keyDown(teleop(), { key: "Tab" });
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(1));
    await waitFor(() =>
      expect(document.activeElement).toBe(cell(0, "Scoring Accuracy (%)")),
    );
  });

  it("cancels on Escape without saving", () => {
    view();
    fireEvent.click(teleop());
    type("99");
    fireEvent.keyDown(teleop(), { key: "Escape" });
    expect(state.saveCorrection).not.toHaveBeenCalled();
    expect(screen.queryByRole("textbox", { name: "Fuel Scored" })).toBeNull();
    expect(teleop().textContent).toBe("10");
  });

  it("refuses a value the form would not take and keeps the cell open", () => {
    view();
    fireEvent.click(teleop());
    type("-2");
    fireEvent.keyDown(teleop(), { key: "Enter" });
    expect(screen.getByRole("alert").textContent).toBe(
      "The lowest value is 0.",
    );
    expect(screen.getByRole("textbox", { name: "Fuel Scored" })).toBeTruthy();
    expect(state.saveCorrection).not.toHaveBeenCalled();
    type("");
    fireEvent.keyDown(teleop(), { key: "Enter" });
    expect(screen.getByRole("alert").textContent).toBe("Enter a number.");
  });

  it("keeps a rating inside its range", () => {
    view();
    fireEvent.click(cell(0, "Scoring Accuracy (%)"));
    fireEvent.change(
      screen.getByRole("textbox", { name: "Scoring Accuracy (%)" }),
      { target: { value: "101" } },
    );
    fireEvent.keyDown(cell(0, "Scoring Accuracy (%)"), { key: "Enter" });
    expect(screen.getByRole("alert").textContent).toBe(
      "The highest value is 100.",
    );
  });

  it("leaves the team, scout and station cells read only", () => {
    view();
    for (const title of [
      "Team Number",
      "Scouter Name",
      "Robot Driver Station",
    ]) {
      const c = cell(0, title);
      expect(c.getAttribute("aria-readonly")).toBe("true");
      fireEvent.click(c);
      fireEvent.keyDown(c, { key: "Enter" });
      fireEvent.keyDown(c, { key: "9" });
      expect(within(c).queryByRole("textbox")).toBeNull();
      expect(within(c).queryByRole("combobox")).toBeNull();
    }
    expect(state.saveCorrection).not.toHaveBeenCalled();
  });

  it("replaces the value when typing on a selected cell", async () => {
    view();
    fireEvent.keyDown(teleop(), { key: "7" });
    const box = screen.getByRole("textbox", {
      name: "Fuel Scored",
    }) as HTMLInputElement;
    expect(box.value).toBe("7");
    fireEvent.keyDown(teleop(), { key: "Enter" });
    await waitFor(() =>
      expect(saved(0).fields).toEqual({ teleopFuelScored: 7 }),
    );
  });

  it("flips a yes/no cell with one click or Space", async () => {
    view();
    fireEvent.click(cell(0, "Defense"));
    await waitFor(() => expect(saved(0).fields).toEqual({ tRdefense: true }));
    fireEvent.keyDown(cell(1, "Defense"), { key: " " });
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(2));
    expect(saved(1).fields).toEqual({ tRdefense: true });
  });

  it("opens a dropdown for a choice cell", async () => {
    view();
    fireEvent.click(cell(0, "Climb Position"));
    const select = screen.getByRole("combobox", { name: "Climb Position" });
    fireEvent.change(select, { target: { value: "Middle" } });
    fireEvent.keyDown(cell(0, "Climb Position"), { key: "Enter" });
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(1));
    expect(saved(0).fields).toEqual({ ePclimb: "Middle" });
  });

  it("moves with the arrow keys and will not blank a counter", async () => {
    view();
    fireEvent.keyDown(teleop(), { key: "ArrowDown" });
    await waitFor(() => expect(document.activeElement).toBe(teleop(1)));
    fireEvent.keyDown(teleop(1), { key: "Delete" });
    expect(state.saveCorrection).not.toHaveBeenCalled();
    expect(screen.getByText("This answer cannot be blank.")).toBeTruthy();
  });

  it("undoes this session's edit and drops the mark", async () => {
    const { rerender } = view();
    fireEvent.click(teleop());
    type("12");
    fireEvent.keyDown(teleop(), { key: "Enter" });
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(1));
    state.corrections = [
      {
        id: "a",
        eventKey: "2027test",
        note: "",
        authorUid: "u1",
        authorDisplayName: "Lead A",
        updatedMs: 5,
        ...saved(0),
      },
    ];
    rerender(tree());
    expect(teleop().textContent).toContain("12");
    expect(teleop().textContent).toContain("Scout entered 10");
    expect(teleop().textContent).toContain("Edited by Scout A");

    fireEvent.keyDown(teleop(), { key: "z", ctrlKey: true });
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(2));
    expect(saved(1).fields).toEqual({});
    expect(saved(1).history.at(-1)).toMatchObject({
      how: "undo",
      from: 12,
      to: 10,
    });
    state.corrections = [
      {
        id: "a",
        eventKey: "2027test",
        note: "",
        authorUid: "u1",
        authorDisplayName: "Lead A",
        updatedMs: 6,
        ...saved(1),
      },
    ];
    rerender(tree());
    expect(teleop().textContent).toBe("10");
  });

  it("says there is nothing to undo", async () => {
    view();
    fireEvent.keyDown(teleop(), { key: "z", ctrlKey: true });
    expect(await screen.findByText("Nothing to undo.")).toBeTruthy();
  });

  it("is not a grid for a role that cannot correct", () => {
    setRoles(ready("mentor"));
    view();
    expect(screen.queryAllByRole("gridcell")).toHaveLength(0);
    fireEvent.click(teleop());
    expect(screen.queryByRole("textbox", { name: "Fuel Scored" })).toBeNull();
  });

  it("shows the delivery line after a save", async () => {
    view();
    fireEvent.click(cell(0, "Defense"));
    await screen.findByText(/Defense, team 1111, Q1/);
  });

  it("keeps both of two quick edits to one entry before the data updates", async () => {
    view();
    fireEvent.click(cell(0, "Defense"));
    fireEvent.click(cell(0, "Passer/Pusher"));
    await waitFor(() => expect(state.saveCorrection).toHaveBeenCalledTimes(2));
    const second = saved(1);
    expect(Object.keys(second.fields).sort()).toEqual(
      ["tRdefense", "tRpasser"].sort(),
    );
    expect(second.history.map((h) => h.field)).toEqual([
      "tRdefense",
      "tRpasser",
    ]);
  });
});

describe("change history", () => {
  const history = (n: number) => ({
    at: n,
    by: "Lead A",
    uid: "u1",
    how: "table",
    field: "teleopFuelScored",
  });
  const corrected = () => {
    state.corrections = [
      {
        id: "a",
        eventKey: "2027test",
        fields: { teleopFuelScored: 14 },
        note: "",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        history: [
          { ...history(1), from: 10, to: 12 },
          {
            ...history(2),
            by: "Lead B",
            uid: "u2",
            how: "form",
            from: 12,
            to: 14,
          },
        ],
        updatedMs: 2,
      },
    ];
  };

  it("marks an edited cell with who edited it and what the scout recorded", () => {
    corrected();
    view();
    const row = within(bodyRows()[0] as HTMLElement);
    expect(row.getByText(/Edited by Lead B/)).toBeTruthy();
    expect(row.getByText("Scout entered 10")).toBeTruthy();
  });

  it("opens every change, newest first", () => {
    corrected();
    view();
    fireEvent.click(
      screen.getByRole("button", { name: "History for team 1111, Q1" }),
    );
    const dialog = document.querySelector("dialog") as HTMLDialogElement;
    const items = within(dialog).getAllByRole("listitem");
    expect(items).toHaveLength(2);
    expect(items[0]?.textContent).toContain("12 to 14");
    expect(items[0]?.textContent).toContain("by Lead B, Form");
    expect(items[1]?.textContent).toContain("10 to 12");
    expect(items[1]?.textContent).toContain("by Lead A, Table");
  });

  it("counts the changes on the button, and says none for an untouched entry", () => {
    corrected();
    view();
    expect(
      screen.getByRole("button", { name: "History for team 1111, Q1" })
        .textContent,
    ).toBe("History (2)");
    const none = screen.getByRole("button", {
      name: "History for team 2222, Q2",
    });
    expect(none.textContent).toBe("History (0)");
    fireEvent.click(none);
    expect(
      screen.getByText("No changes. This is what the scout entered."),
    ).toBeTruthy();
  });

  it("does not mark a field changed back to the scout's value", () => {
    state.corrections = [
      {
        id: "a",
        eventKey: "2027test",
        fields: {},
        note: "",
        authorUid: "u1",
        authorDisplayName: "Lead A",
        history: [
          { ...history(1), from: 10, to: 12 },
          { ...history(2), how: "undo", from: 12, to: 10 },
        ],
        updatedMs: 2,
      },
    ];
    view();
    expect(screen.queryByText(/Edited by/)).toBeNull();
    expect(
      screen.getByRole("button", { name: "History for team 1111, Q1" })
        .textContent,
    ).toBe("History (2)");
  });

  it("offers History and the form on a phone", () => {
    corrected();
    setWidth(400);
    view();
    const first = within(screen.getAllByRole("listitem")[0] as HTMLElement);
    expect(first.getByRole("button", { name: /^History for/ })).toBeTruthy();
    expect(first.getByRole("button", { name: /^Form for/ })).toBeTruthy();
  });
});

describe("new data while editing", () => {
  const arrive = () => {
    state.entries = [
      ...state.entries,
      entry("c", "2027test_qm3", 3333, "Scout C"),
    ];
  };

  it("holds the rows and offers a refresh when an entry arrives", () => {
    const { rerender } = view();
    act(() =>
      tableEl()
        .querySelector<HTMLElement>('[data-cell][tabindex="0"]')
        ?.focus(),
    );
    arrive();
    rerender(tree());
    expect(bodyRows()).toHaveLength(2);
    expect(screen.getByText(/1 new entry arrived/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "New data, refresh" }));
    expect(bodyRows()).toHaveLength(3);
  });

  it("shows new entries at once when the grid was never used", () => {
    const { rerender } = view();
    arrive();
    rerender(tree());
    expect(bodyRows()).toHaveLength(3);
  });
});
