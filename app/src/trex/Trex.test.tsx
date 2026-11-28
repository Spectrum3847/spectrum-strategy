// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import type { TrexReport } from "../data/parse";
import { parseAssignments, parseTeamList } from "./assignments";
import { TrexAssignments } from "./TrexAssignments";
import { TrexDatabase } from "./TrexDatabase";
import { TrexReportForm } from "./TrexReportForm";

const state = vi.hoisted(() => ({
  auth: { status: "signed-in", uid: "u1", displayName: "Scout A" } as Record<
    string,
    unknown
  >,
  reports: [] as unknown[],
  outbox: [] as unknown[],
  tables: {} as Record<string, unknown>,
  enqueue: vi.fn(),
  enqueueDelete: vi.fn((..._args: unknown[]) => Promise.resolve("o2")),
}));

vi.mock("../auth/AuthProvider", () => ({ useAuth: () => state.auth }));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../data/useCollections", () => ({
  useTrexReports: () => ({ items: state.reports, ready: true, failed: false }),
}));
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027test",
    status: "ready",
    fetchedAt: null,
    teams: [{ number: 1111, nickname: "Alpha Bots" }],
    rankings: [],
    matches: [],
  }),
}));
vi.mock("../outbox/outbox", () => ({
  enqueueWrite: (...args: unknown[]) => state.enqueue(...args),
  enqueueDelete: (...args: unknown[]) => state.enqueueDelete(...args),
  dismissItem: () => undefined,
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("./useAssignments", () => ({ useTrexTables: () => state.tables }));

const report = (patch: Partial<TrexReport>): TrexReport => ({
  id: "r1",
  trait: "defense",
  teamNumber: 1111,
  matchNumber: 4,
  eventName: "Test Regional",
  eventKey: "2027test",
  report: "Pins for too long",
  rating: null,
  scoutName: "Scout B",
  authorUid: "u2",
  updatedAt: "2027-03-05T18:00:00.000Z",
  ...patch,
});

const show = (ui: React.ReactNode) => render(<MemoryRouter>{ui}</MemoryRouter>);

beforeEach(() => {
  setRoles(ready("scouter"));
  state.auth = { status: "signed-in", uid: "u1", displayName: "Scout A" };
  state.reports = [];
  state.outbox = [];
  state.tables = {};
  state.enqueue = vi.fn(async (path: string) => {
    state.outbox = [
      {
        id: "o1",
        path,
        data: {},
        label: "T-REx",
        createdAt: "",
        status: "in-database",
      },
    ];
    return "o1";
  });
});

afterEach(() => {
  cleanup();
  localStorage.clear();
});

const type = (label: string | RegExp, value: string) =>
  fireEvent.change(screen.getByLabelText(label), { target: { value } });

const rate = (n: number) =>
  fireEvent.click(screen.getByRole("radio", { name: String(n) }));

describe("TrexReportForm", () => {
  it("saves a report through the outbox and confirms the database", async () => {
    show(<TrexReportForm />);
    fireEvent.click(screen.getByRole("button", { name: "Fuel scoring" }));
    type("Team number", "1111");
    type("Match number", "7");
    rate(4);
    type("Report", "  Fast cycles, misses far shots ");
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));

    await screen.findByText("Report saved for team 1111");
    expect(screen.getByText("In the database")).toBeTruthy();
    expect(state.enqueue).toHaveBeenCalledTimes(1);
    const [path, doc] = state.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(path).toBe(`trexTraitReports/${String(doc.id)}`);
    expect(doc).toMatchObject({
      trait: "fuelScoring",
      teamNumber: 1111,
      matchNumber: 7,
      eventName: "2027test",
      eventKey: "2027test",
      report: "Fast cycles, misses far shots",
      rating: 4,
      authorUid: "u1",
      authorDisplayName: "Scout A",
    });
    expect(localStorage.getItem("ss.trex.draft")).toBeNull();
  });

  it("starts the next report on the same trait and event", async () => {
    show(<TrexReportForm />);
    fireEvent.click(screen.getByRole("button", { name: "Autonomous" }));
    type("Team number", "1111");
    type("Match number", "7");
    rate(5);
    type("Report", "Two fuel in auto");
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));
    fireEvent.click(await screen.findByRole("button", { name: "New report" }));
    expect(
      screen
        .getByRole("button", { name: "Autonomous" })
        .getAttribute("aria-pressed"),
    ).toBe("true");
    expect(
      (screen.getByLabelText("Team number") as HTMLInputElement).value,
    ).toBe("");
    expect((screen.getByLabelText("Report") as HTMLTextAreaElement).value).toBe(
      "",
    );
    expect(
      (screen.getByRole("radio", { name: "5" }) as HTMLInputElement).checked,
    ).toBe(false);
  });

  it("names what is missing and writes nothing", () => {
    show(<TrexReportForm />);
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));
    expect(screen.getByRole("alert").textContent).toBe("Enter a team number.");
    type("Team number", "1111");
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));
    expect(screen.getByRole("alert").textContent).toBe("Enter a match number.");
    type("Match number", "7");
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));
    expect(screen.getByRole("alert").textContent).toBe(
      "Pick a rating from 1 to 5.",
    );
    expect(state.enqueue).not.toHaveBeenCalled();
  });

  it("keeps the typed answers when the outbox write fails", async () => {
    state.enqueue = vi.fn(() => Promise.reject(new Error("disk full")));
    show(<TrexReportForm />);
    type("Team number", "1111");
    type("Match number", "7");
    rate(3);
    type("Report", "Text");
    fireEvent.click(screen.getByRole("button", { name: "Save report" }));
    await waitFor(() =>
      expect(screen.getByRole("alert").textContent).toMatch(
        /Nothing was recorded/,
      ),
    );
    expect((screen.getByLabelText("Report") as HTMLTextAreaElement).value).toBe(
      "Text",
    );
  });

  it("will not save while signed out", () => {
    state.auth = { status: "signed-out", uid: null, displayName: null };
    show(<TrexReportForm />);
    const button = screen.getByRole("button", { name: "Sign in to save" });
    expect((button as HTMLButtonElement).disabled).toBe(true);
  });

  it("reuses the event name other reports carry", () => {
    state.reports = [report({ eventName: "Test Regional" })];
    show(<TrexReportForm />);
    expect((screen.getByLabelText("Event") as HTMLInputElement).value).toBe(
      "Test Regional",
    );
  });

  it("restores an unsent draft", () => {
    localStorage.setItem(
      "ss.trex.draft",
      JSON.stringify({
        trait: "defense",
        team: "2222",
        rating: 3,
        report: "Half typed",
      }),
    );
    show(<TrexReportForm />);
    expect(screen.getByText("Restored your unsaved report.")).toBeTruthy();
    expect(
      (screen.getByLabelText("Team number") as HTMLInputElement).value,
    ).toBe("2222");
    expect(
      screen
        .getByRole("button", { name: "Defense" })
        .getAttribute("aria-pressed"),
    ).toBe("true");
    expect(
      (screen.getByRole("radio", { name: "3" }) as HTMLInputElement).checked,
    ).toBe(true);
  });

  it("offers a 1 to 5 radio group with the ends of the scale named", () => {
    show(<TrexReportForm />);
    const group = screen.getByRole("group", { name: "Rating of this trait" });
    expect(within(group).getAllByRole("radio")).toHaveLength(5);
    expect(group.getAttribute("aria-describedby")).toBeTruthy();
    expect(screen.getByText("1 is poor")).toBeTruthy();
    expect(screen.getByText("5 is excellent")).toBeTruthy();
    rate(2);
    rate(4);
    expect(
      (screen.getByRole("radio", { name: "2" }) as HTMLInputElement).checked,
    ).toBe(false);
    expect(
      (screen.getByRole("radio", { name: "4" }) as HTMLInputElement).checked,
    ).toBe(true);
  });

  it("shows the lookout notes for the chosen trait", () => {
    show(<TrexReportForm />);
    fireEvent.click(screen.getByRole("button", { name: "Defense" }));
    expect(screen.getByText("Lookout notes for Defense")).toBeTruthy();
    expect(screen.getByText(/Pin fouls/)).toBeTruthy();
  });
});

describe("TrexDatabase", () => {
  beforeEach(() => {
    state.reports = [
      report({ id: "a" }),
      report({ id: "b", trait: "autonomous", report: "Two in auto" }),
      report({ id: "c", teamNumber: 2222, report: "Pushed hard" }),
      report({ id: "d", teamNumber: 3333, eventKey: "2026old" }),
    ];
  });

  it("groups reports by team for leads", () => {
    setRoles(ready("strategy"));
    show(<TrexDatabase />);
    expect(screen.getByText("Team 1111")).toBeTruthy();
    expect(screen.getByText("2 reports")).toBeTruthy();
    expect(screen.getByText("Team 2222")).toBeTruthy();
    expect(screen.queryByText("Team 3333")).toBeNull();
    expect(screen.getByText("Two in auto")).toBeTruthy();
  });

  it("filters by trait, event and team", () => {
    setRoles(ready("strategy"));
    show(<TrexDatabase />);
    fireEvent.click(screen.getByRole("button", { name: "All events" }));
    expect(screen.getByText("Team 3333")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Autonomous" }));
    expect(screen.getByText("Team 1111")).toBeTruthy();
    expect(screen.queryByText("Team 2222")).toBeNull();
    fireEvent.click(screen.getByRole("button", { name: "All traits" }));
    type("Search team number", "22");
    expect(screen.queryByText("Team 1111")).toBeNull();
    expect(screen.getByText("Team 2222")).toBeTruthy();
  });

  it("says when nothing matches", () => {
    setRoles(ready("strategy"));
    state.reports = [];
    show(<TrexDatabase />);
    expect(screen.getByText("No T-REx reports yet.")).toBeTruthy();
  });

  it("lets scouts read the reports without a team page link", () => {
    show(<TrexDatabase />);
    expect(screen.getByText("Team 1111")).toBeTruthy();
    expect(screen.queryByRole("link", { name: "Open team page" })).toBeNull();
    cleanup();
    setRoles(ready("strategy"));
    show(<TrexDatabase />);
    expect(
      screen
        .getAllByRole("link", { name: "Open team page" })[0]
        ?.getAttribute("href"),
    ).toBe("/teams/1111");
  });

  it("shows each report's rating when it has one", () => {
    state.reports = [
      report({ id: "a", rating: 4 }),
      report({ id: "b", report: "Unrated note" }),
    ];
    show(<TrexDatabase />);
    expect(screen.getAllByText("Rating 4 of 5")).toHaveLength(1);
    expect(screen.getByText("Unrated note")).toBeTruthy();
  });
});

describe("TrexAssignments", () => {
  const tables = (ok = true) => ({
    assignments: parseAssignments({
      columns: [
        { key: "1", name: "Defense", names: ["Scout A", "Scout B"] },
        { key: "2", name: "Autonomous", names: ["Scout C"] },
      ],
      updatedAt: "2020-03-05T18:04:05.123Z",
    }),
    teamList: parseTeamList({
      columns: [{ key: "x", name: "Defense", teams: ["1111", "2222"] }],
    }),
    ready: true,
    failed: !ok,
    missing: false,
  });

  it("shows who covers which teams and marks the viewer", () => {
    state.tables = tables();
    show(<TrexAssignments />);
    const defense = screen
      .getByRole("heading", { name: /Defense/ })
      .closest("li");
    expect(defense?.getAttribute("data-mine")).toBe("true");
    expect(within(defense as HTMLElement).getByText("Scout B")).toBeTruthy();
    expect(within(defense as HTMLElement).getByText("1111")).toBeTruthy();
    const auto = screen
      .getByRole("heading", { name: /Autonomous/ })
      .closest("li");
    expect(auto?.getAttribute("data-mine")).toBe("false");
    expect(within(auto as HTMLElement).getByText("No teams yet")).toBeTruthy();
    expect(screen.getByText(/Total teams: 2/)).toBeTruthy();
  });

  it("keeps team numbers plain for scouts and linked for leads", () => {
    state.tables = tables();
    show(<TrexAssignments />);
    expect(screen.queryByRole("link", { name: "1111" })).toBeNull();
    cleanup();
    setRoles(ready("strategy"));
    show(<TrexAssignments />);
    expect(screen.getByRole("link", { name: "1111" })).toBeTruthy();
  });

  it("says when nothing has been loaded or added", () => {
    state.tables = {
      assignments: parseAssignments(null),
      teamList: parseTeamList(null),
      ready: true,
      failed: false,
      missing: true,
    };
    show(<TrexAssignments />);
    expect(screen.getByText(/No assignments on this device yet/)).toBeTruthy();
    cleanup();
    state.tables = { ...state.tables, missing: false };
    show(<TrexAssignments />);
    expect(
      screen.getByText("No T-REx traits have been added yet."),
    ).toBeTruthy();
  });

  it("warns when the read failed", () => {
    state.tables = tables(false);
    show(<TrexAssignments />);
    expect(screen.getByRole("alert").textContent).toMatch(/older copy/);
  });

  it("says when the browser blocks the copy", async () => {
    state.tables = tables();
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockRejectedValue(new Error("denied")) },
    });
    show(<TrexAssignments />);
    fireEvent.click(screen.getByRole("button", { name: "Copy as text" }));
    expect(await screen.findByText(/Could not copy/)).toBeTruthy();
  });

  describe("editing", () => {
    const lead = () => {
      setRoles(ready("strategy"));
      state.tables = tables();
      show(<TrexAssignments />);
      fireEvent.click(screen.getByRole("button", { name: "Edit" }));
    };
    const nth = (name: string, i: number) =>
      screen.getAllByRole("button", { name })[i] as HTMLElement;
    const written = (n = 0) =>
      state.enqueue.mock.calls[n] as [string, Record<string, unknown>, string];

    it("offers editing to leads only", () => {
      state.tables = tables();
      for (const role of ["scouter", "mentor"] as const) {
        setRoles(ready(role));
        show(<TrexAssignments />);
        expect(screen.queryByRole("button", { name: "Edit" })).toBeNull();
        cleanup();
      }
      setRoles(ready("admin"));
      show(<TrexAssignments />);
      expect(screen.getByRole("button", { name: "Edit" })).toBeTruthy();
    });

    it("saves an added scouter to the assignments document", async () => {
      lead();
      const defense = screen.getAllByLabelText("New Scouter")[0];
      fireEvent.change(defense as HTMLElement, {
        target: { value: " Scout D " },
      });
      fireEvent.click(nth("Add", 0));
      await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
      const [path, doc, label] = written();
      expect(path).toBe("appConfig/trexAssignments");
      expect(label).toBe("T-REx assignments");
      expect(doc).toMatchObject({
        authorUid: "u1",
        authorDisplayName: "Scout A",
        columns: [
          {
            key: "1",
            name: "Defense",
            names: ["Scout A", "Scout B", "Scout D"],
          },
          { key: "2", name: "Autonomous", names: ["Scout C"] },
        ],
      });
      expect(doc.updatedAtTs).toBeTruthy();
      expect(await screen.findByText("In the database")).toBeTruthy();
    });

    it("saves a team to the team list and keeps its title", async () => {
      lead();
      fireEvent.change(screen.getAllByLabelText("New Team")[0] as HTMLElement, {
        target: { value: "3333" },
      });
      fireEvent.click(nth("Add", 1));
      await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
      const [path, doc] = written();
      expect(path).toBe("appConfig/trexTeamList");
      expect(doc).toMatchObject({
        title: "",
        columns: [
          { key: "x", name: "Defense", teams: ["1111", "2222", "3333"] },
        ],
      });
    });

    it("renames a trait in both tables", async () => {
      lead();
      const name = screen.getAllByLabelText(
        "Trait name",
      )[0] as HTMLInputElement;
      fireEvent.change(name, { target: { value: "Pushing" } });
      fireEvent.blur(name);
      await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(2));
      const paths = state.enqueue.mock.calls.map((c) => c[0]);
      expect(paths).toEqual([
        "appConfig/trexAssignments",
        "appConfig/trexTeamList",
      ]);
      expect(written(1)[1].columns).toEqual([
        { key: "x", name: "Pushing", teams: ["1111", "2222"] },
      ]);
    });

    it("puts the old name back when a field is cleared", () => {
      lead();
      const name = screen.getAllByLabelText(
        "Trait name",
      )[0] as HTMLInputElement;
      fireEvent.change(name, { target: { value: " " } });
      fireEvent.blur(name);
      expect(name.value).toBe("Defense");
      expect(state.enqueue).not.toHaveBeenCalled();
    });

    it("asks before removing a trait", async () => {
      lead();
      fireEvent.click(nth("Remove trait", 1));
      expect(state.enqueue).not.toHaveBeenCalled();
      fireEvent.click(screen.getByRole("button", { name: "Keep it" }));
      expect(state.enqueue).not.toHaveBeenCalled();
      fireEvent.click(nth("Remove trait", 1));
      fireEvent.click(screen.getByRole("button", { name: "Remove" }));
      await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
      expect((written()[1].columns as unknown[]).length).toBe(1);
    });

    it("adds a trait as a scouter column and a team column", async () => {
      lead();
      fireEvent.change(screen.getByLabelText("New trait"), {
        target: { value: "Climb" },
      });
      fireEvent.click(screen.getByRole("button", { name: "Add trait" }));
      await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(2));
      expect(written(0)[1].columns).toHaveLength(3);
      expect(written(1)[1].columns).toHaveLength(2);
    });

    it("adds a pasted list in one write", async () => {
      lead();
      fireEvent.click(nth("Paste a list", 1));
      fireEvent.change(screen.getByLabelText("Paste Teams"), {
        target: { value: "2222\n4444, 5555" },
      });
      fireEvent.click(screen.getByRole("button", { name: "Add all" }));
      await waitFor(() => expect(state.enqueue).toHaveBeenCalledTimes(1));
      expect(written()[1].columns).toEqual([
        { key: "x", name: "Defense", teams: ["1111", "2222", "4444", "5555"] },
      ]);
    });

    it("shows the new text before the database sends it back", async () => {
      lead();
      fireEvent.change(
        screen.getAllByLabelText("New Scouter")[1] as HTMLElement,
        {
          target: { value: "Scout Z" },
        },
      );
      fireEvent.click(nth("Add", 2));
      expect(await screen.findByDisplayValue("Scout Z")).toBeTruthy();
    });

    it("shows each table's save state on its own line", () => {
      const item = (path: string, status: string, createdAt: string) => ({
        id: path,
        path,
        data: {},
        label: "T-REx",
        createdAt,
        status,
        ...(status === "refused" ? { error: "Not allowed." } : {}),
      });
      state.outbox = [
        item("appConfig/trexTeamList", "in-database", "2027-03-01T10:00:02Z"),
        item("appConfig/trexAssignments", "refused", "2027-03-01T10:00:01Z"),
      ];
      lead();
      const line = (name: string) =>
        screen.getByText(new RegExp(`^${name}:`)).closest("p")?.textContent;
      expect(line("Assignments")).toMatch(/Refused.*Not allowed\./);
      expect(line("Team list")).toMatch(/In the database/);
    });

    it("shows the reason when a write is refused", async () => {
      state.enqueue = vi.fn(async () => {
        throw new Error("Training mode sends nothing.");
      });
      lead();
      fireEvent.change(
        screen.getAllByLabelText("New Scouter")[0] as HTMLElement,
        {
          target: { value: "Scout D" },
        },
      );
      fireEvent.click(nth("Add", 0));
      expect((await screen.findByRole("alert")).textContent).toMatch(
        /Training/,
      );
      expect(screen.queryByDisplayValue("Scout D")).toBeNull();
    });
  });
});

describe("TrexDatabase delete", () => {
  beforeEach(() => {
    state.enqueueDelete.mockClear();
    state.reports = [
      report({ id: "mine", authorUid: "u1", report: "My note" }),
      report({ id: "theirs", trait: "autonomous", report: "Their note" }),
    ];
  });

  it("lets a scout delete only their own report, after a confirm", async () => {
    show(<TrexDatabase />);
    fireEvent.click(screen.getByText("Team 1111"));
    expect(screen.getAllByRole("button", { name: /^Delete/ })).toHaveLength(1);
    fireEvent.click(screen.getByRole("button", { name: /^Delete/ }));
    expect(state.enqueueDelete).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: /^Confirm delete/ }));
    await waitFor(() =>
      expect(state.enqueueDelete).toHaveBeenCalledWith(
        "trexTraitReports/mine",
        expect.any(String),
      ),
    );
  });

  it("lets a lead delete any report", () => {
    setRoles(ready("strategy"));
    show(<TrexDatabase />);
    fireEvent.click(screen.getByText("Team 1111"));
    expect(screen.getAllByRole("button", { name: /^Delete/ })).toHaveLength(2);
  });

  it("gives a mentor no delete", () => {
    setRoles(ready("mentor"));
    show(<TrexDatabase />);
    fireEvent.click(screen.getByText("Team 1111"));
    expect(screen.queryByRole("button", { name: /^Delete/ })).toBeNull();
  });
});
