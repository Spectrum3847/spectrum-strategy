// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  within,
} from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import bundled from "../../../assets/scout_config_default.json";
import { ready, setRoles } from "../auth/rolesMock";
import type {
  EventEntry,
  PitEntry,
  PrescoutEntry,
  TrexReport,
} from "../data/parse";
import type { PickList } from "../picks/pickList";
import { parseConfig } from "../scout/config";
import { Team } from "./TeamPage";

const config = parseConfig(bundled);

const state = vi.hoisted(() => ({
  signedIn: true,
  entries: [] as unknown[],
  pit: [] as unknown[],
  prescout: [] as unknown[],
  trex: [] as unknown[],
  notes: [] as unknown[],
  corrections: [] as unknown[],
  tba: {} as Record<string, unknown>,
  lists: [] as unknown[],
  save: vi.fn((..._args: unknown[]) => Promise.resolve("id")),
  saveCorrection: vi.fn((..._args: unknown[]) => Promise.resolve()),
}));

vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: state.signedIn ? "signed-in" : "signed-out",
    uid: "u1",
    displayName: "Lead A",
  }),
}));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../data/useTeamNotes", () => ({
  useTeamNotes: () => ({ items: state.notes, ready: true, failed: false }),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../photos/service", () => import("../photos/fakeService"));
vi.mock("../assistant/firestore", () => ({
  firestoreApi: {
    watchSummary: () => () => undefined,
    post: () => Promise.resolve(),
    remove: () => Promise.resolve(),
  },
}));
vi.mock("../scout/ScoutData", () => ({
  useScoutData: () => ({ config, eventKey: "2027test", schedule: [] }),
}));
vi.mock("../data/entries", () => ({
  useEventEntries: () => ({ items: state.entries, ready: true, failed: false }),
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
  const { parseConfig: parse } = await import("../scout/config");
  const pit = await import("../../../assets/pit_scout_config_default.json");
  const prescout = await import("../../../assets/prescout_config_default.json");
  return {
    usePitEntries: () => ({ items: state.pit, ready: true, failed: false }),
    usePrescoutEntries: () => ({
      items: state.prescout,
      ready: true,
      failed: false,
    }),
    useTrexReports: () => ({ items: state.trex, ready: true, failed: false }),
    useFormConfig: (kind: string) =>
      parse(kind === "pit" ? pit.default : prescout.default),
  };
});
vi.mock("../data/useTbaEvent", () => ({ useTbaEvent: () => state.tba }));
vi.mock("../picks/usePickLists", () => ({
  usePickLists: () => ({ items: state.lists, ready: true, failed: false }),
  savePickList: (...args: unknown[]) => state.save(...args),
  pickListPath: (id: string) => `pickLists/${id}`,
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => [] }));
vi.mock("../outbox/outbox", () => ({ dismissItem: () => undefined }));

const entry = (
  id: string,
  key: string,
  values: Record<string, unknown>,
): EventEntry => ({
  id,
  teamNumber: 1111,
  alliance: "Red",
  tbaMatchKey: key,
  scoutName: "Scout A",
  updatedAt: "2027-03-01T10:00:00.000Z",
  fieldValues: values,
});

const tba = {
  eventKey: "2027test",
  status: "ready",
  fetchedAt: "2027-03-01T12:00:00.000Z",
  teams: [
    { number: 1111, nickname: "Alpha Bots" },
    { number: 2222, nickname: "Beta" },
  ],
  rankings: [{ team: 1111, rank: 3, wins: 4, losses: 1, ties: 0 }],
  matches: [
    {
      key: "2027test_qm1",
      level: "qm",
      red: [1111, 2222, 3333],
      blue: [4444, 5555, 6666],
      redScore: 40,
      blueScore: 35,
      winner: "red",
    },
    {
      key: "2027test_qm9",
      level: "qm",
      red: [4444, 5555, 6666],
      blue: [1111, 2222, 3333],
      redScore: null,
      blueScore: null,
      winner: null,
    },
  ],
};

const sectionOf = (name: string) =>
  screen.getByRole("heading", { name }).closest("section") as HTMLElement;
const comments = () => sectionOf("Comments and notes");
const entriesSection = () => sectionOf("Scout entries");

function view(path = "/teams/1111") {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/teams/:team" element={<Team />} />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(() => {
  localStorage.clear();
  state.signedIn = true;
  state.entries = [];
  state.pit = [];
  state.prescout = [];
  state.trex = [];
  state.notes = [];
  state.corrections = [];
  state.saveCorrection.mockClear();
  setRoles(ready("strategy"));
  state.tba = tba;
  state.lists = [];
  state.save.mockClear();
});
afterEach(cleanup);

describe("team page", () => {
  it("lists the team note read only among the comments", () => {
    state.notes = [
      {
        id: "2027test_1111",
        eventKey: "2027test",
        teamNumber: 1111,
        text: "Defends the ramp",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        updatedMs: Date.parse("2027-03-01T10:00:00Z"),
      },
    ];
    view();
    const section = comments();
    const note = within(section)
      .getByText("Defends the ramp")
      .closest("li") as HTMLElement;
    expect(within(note).getByText("Team note")).toBeTruthy();
    expect(within(note).getByText(/Lead B/)).toBeTruthy();
    expect(screen.queryByRole("textbox")).toBeNull();
  });

  it("links a lead and a scouter to the prescout form for the team", () => {
    view();
    expect(
      screen.getByRole("link", { name: "Pre-scout" }).getAttribute("href"),
    ).toBe("/scout/prescout/1111");
    cleanup();
    setRoles(ready("scouter"));
    view();
    expect(screen.getByRole("link", { name: "Pre-scout" })).toBeTruthy();
  });

  it("shows honest empty states when nothing is recorded", () => {
    view();
    expect(screen.getByRole("heading", { name: "Team 1111" })).toBeTruthy();
    expect(screen.getByText("Alpha Bots")).toBeTruthy();
    expect(screen.getByText("Rank 3, 4-1-0")).toBeTruthy();
    expect(
      screen.getAllByText("No scouting entries for this team yet."),
    ).toHaveLength(2);
    expect(screen.getByText("No pit entry yet.")).toBeTruthy();
    expect(screen.getByText("No T-REx reports yet.")).toBeTruthy();
    expect(screen.getByText("No prescout entries yet.")).toBeTruthy();
    expect(screen.getByText(/A trend needs 3 scored matches/)).toBeTruthy();
  });

  it("lists the team's matches with results and links to each match", () => {
    view();
    const matches = screen
      .getByRole("heading", { name: "Matches" })
      .closest("section");
    const links = within(matches as HTMLElement).getAllByRole("link");
    expect(links.map((l) => l.getAttribute("href"))).toEqual([
      "/matches/2027test_qm1",
      "/matches/2027test_qm9",
    ]);
    expect(
      within(links[0] as HTMLElement).getByText("Won 40 to 35"),
    ).toBeTruthy();
    expect(
      within(links[1] as HTMLElement).getByText("Not played"),
    ).toBeTruthy();
  });

  it("shows the stats table, then tiles, from the scouted entries", () => {
    state.entries = [
      entry("a", "2027test_qm1", { teleopFuelScored: 10, tRdefense: true }),
      entry("b", "2027test_qm9", { teleopFuelScored: 20, tRdefense: false }),
      entry("c", "2027test_qm9", { teleopFuelScored: 30, tRdefense: false }),
    ];
    view();
    const table = screen.getByRole("table", {
      name: "Team 1111 scouted stats",
    });
    const teleop = within(table).getByRole("row", { name: /Fuel Scored/ });
    expect(
      within(teleop)
        .getAllByRole("cell")
        .map((c) => c.textContent),
    ).toEqual(["17.5±7.5", "-", "25", "17.5", "2"]);
    const stats = screen
      .getByRole("heading", { name: "Event stats" })
      .closest("section") as HTMLElement;
    expect(within(stats).getByText("Defense")).toBeTruthy();
    expect(within(stats).getByText("1 / 2")).toBeTruthy();
    expect(
      screen.getByText(
        "2 matches scouted. A match with several scouts counts once.",
      ),
    ).toBeTruthy();

    fireEvent.click(screen.getByRole("button", { name: "Tiles" }));
    expect(
      screen.queryByRole("table", { name: "Team 1111 scouted stats" }),
    ).toBeNull();
    expect(screen.getAllByText("Best 25, IQM 17.5, n 2")).toHaveLength(2);
    expect(screen.getAllByText("±7.5")).toHaveLength(2);
    expect(localStorage.getItem("ss.team.statsView")).toBe('"tiles"');
  });

  it("says how many matches had no breakdown and tags a clear trend", () => {
    state.entries = [
      ...[10, 12, 8, 20, 22, 18].map((n, i) =>
        entry(`m${i}`, `2027test_qm${i + 1}`, {
          teleopFuelScored: n,
          dieCard: false,
        }),
      ),
      entry("late", "2027test_qm7", { teleopFuelScored: 0, dieCard: true }),
    ];
    view();
    expect(screen.getByText("6 of 7 matches without a breakdown")).toBeTruthy();
    expect(screen.getByText("Improving +10")).toBeTruthy();
    const table = screen.getByRole("table", {
      name: "Team 1111 scouted stats",
    });
    const total = within(table).getByRole("row", { name: /Match total/ });
    expect(
      within(total)
        .getAllByRole("cell")
        .map((c) => c.textContent)
        .slice(0, 2),
    ).toEqual(["15±2.4", "10.5 to 19.5"]);
  });

  it("shows no trend tag for a steady team", () => {
    state.entries = [10, 11, 10, 11, 10, 11].map((n, i) =>
      entry(`m${i}`, `2027test_qm${i + 1}`, { teleopFuelScored: n }),
    );
    view();
    expect(screen.getByText("6 of 6 matches without a breakdown")).toBeTruthy();
    expect(screen.queryByText(/^Improving|^Declining/)).toBeNull();
    expect(screen.getByText("Typical counts every match.")).toBeTruthy();
    expect(screen.queryByText("Typical leaves out:")).toBeNull();
  });

  it("lists each match typical leaves out, with its reason and a link", () => {
    state.entries = [
      ...[40, 42, 41, 43, 41, 90].map((n, i) =>
        entry(`m${i}`, `2027test_qm${i + 1}`, {
          teleopFuelScored: n,
          dieCard: false,
        }),
      ),
      entry("late", "2027test_qm7", { teleopFuelScored: 0, dieCard: true }),
    ];
    view();
    const line = screen.getByText("Typical leaves out:").parentElement;
    const found = within(line as HTMLElement);
    expect(found.getByRole("link", { name: "Q6" }).getAttribute("href")).toBe(
      "/matches/2027test_qm6",
    );
    expect(found.getByText("90, far above usual")).toBeTruthy();
    expect(found.getByRole("link", { name: "Q7" }).getAttribute("href")).toBe(
      "/matches/2027test_qm7",
    );
    expect(found.getByText("0, breakdown")).toBeTruthy();
    expect(screen.queryByText("Typical counts every match.")).toBeNull();
  });

  it("builds a comment summary and lists comments with match links", () => {
    state.entries = [
      entry("a", "2027test_qm1", {
        dieCard: true,
        comments: "Lost drive power",
      }),
      entry("b", "2027test_qm9", { dieCard: false, scouter: "Scout A" }),
    ];
    view();
    const section = comments();
    expect(
      within(section).getByText("Disconnect/Die: 1 of 2 matches"),
    ).toBeTruthy();
    expect(within(section).getByText("Lost drive power")).toBeTruthy();
    expect(section.querySelectorAll(".team-comment")).toHaveLength(1);
    const cites = within(section).getAllByRole("link", { name: "Q1" });
    expect(cites[0]?.getAttribute("href")).toBe("/matches/2027test_qm1");
  });

  describe("scout entry corrections", () => {
    const fix = (fields: Record<string, unknown>, note = "", id = "a") => ({
      id,
      eventKey: "2027test",
      fields,
      note,
      authorUid: "u2",
      authorDisplayName: "Lead B",
      history: [],
      updatedMs: Date.parse("2027-03-02T10:00:00Z"),
    });
    const open = () => within(entriesSection());
    const correct = () => {
      const entries = open();
      fireEvent.click(entries.getByRole("button", { name: "Correct Q1" }));
      return entries;
    };

    it("uses the corrected value in the stats and keeps a marker", () => {
      state.entries = [
        entry("a", "2027test_qm1", { teleopFuelScored: 10 }),
        entry("b", "2027test_qm9", { teleopFuelScored: 20 }),
      ];
      state.corrections = [
        fix({ teleopFuelScored: 30 }, "Counted from video", "b"),
      ];
      view();
      const table = screen.getByRole("table", {
        name: "Team 1111 scouted stats",
      });
      const row = within(table).getByRole("row", { name: /Fuel Scored/ });
      expect(
        within(row)
          .getAllByRole("cell")
          .map((c) => c.textContent)[0],
      ).toBe("20±10");
      const entries = open();
      const q9 = entries.getByRole("row", { name: /^Q9/ });
      expect(within(q9).getByText("30")).toBeTruthy();
      expect(within(q9).getByText("Scout entered 20")).toBeTruthy();
      expect(within(q9).getByText(/^Edited by Lead B/)).toBeTruthy();
      expect(within(q9).getByText(/^Lead B, /)).toBeTruthy();
      expect(within(q9).getByText("Counted from video")).toBeTruthy();
    });

    it("lets a lead correct a value and saves it beside the entry", () => {
      state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
      view();
      const entries = correct();
      const teleop = within(entries.getByRole("group", { name: "Teleop" }));
      fireEvent.click(
        teleop.getByRole("button", { name: "Fuel Scored plus 5" }),
      );
      fireEvent.change(entries.getByRole("textbox", { name: /Why/ }), {
        target: { value: "Video" },
      });
      fireEvent.click(entries.getByRole("button", { name: "Save correction" }));
      expect(state.saveCorrection).toHaveBeenCalledTimes(1);
      const [saved, label] = state.saveCorrection.mock.calls[0] as [
        Record<string, unknown>,
        string,
      ];
      expect(saved).toMatchObject({
        id: "a",
        eventKey: "2027test",
        fields: { teleopFuelScored: 15 },
        note: "Video",
        authorUid: "u1",
        authorDisplayName: "Scout A",
        history: [
          expect.objectContaining({
            field: "teleopFuelScored",
            from: 10,
            to: 15,
            how: "form",
            by: "Scout A",
          }),
        ],
      });
      expect(label).toBe("Correction for team 1111, Q1");
    });

    it("keeps Save off until something changes", () => {
      state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
      view();
      const entries = correct();
      expect(
        (
          entries.getByRole("button", {
            name: "Save correction",
          }) as HTMLButtonElement
        ).disabled,
      ).toBe(true);
    });

    it("removes a correction by saving it with no fields", () => {
      state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
      state.corrections = [fix({ teleopFuelScored: 30 })];
      view();
      const entries = correct();
      fireEvent.click(
        entries.getByRole("button", { name: "Remove correction" }),
      );
      expect(state.saveCorrection).toHaveBeenCalledTimes(1);
      expect(state.saveCorrection.mock.calls[0]?.[0]).toMatchObject({
        id: "a",
        fields: {},
        note: "",
        updatedMs: Date.parse("2027-03-02T10:00:00Z"),
      });
    });

    it("gives no Correct button to anyone but a lead", () => {
      state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
      setRoles(ready("scouter"));
      view();
      const entries = open();
      expect(entries.queryByRole("button", { name: /Correct/ })).toBeNull();
      expect(entries.getByText("10")).toBeTruthy();
    });

    it("goes back to the table from the correct view", () => {
      state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
      view();
      const entries = correct();
      fireEvent.click(
        entries.getByRole("button", { name: "Back to the entries" }),
      );
      expect(entries.getByRole("table")).toBeTruthy();
    });

    it("lists entries to open on a phone, with Correct inside", () => {
      state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
      const width = window.innerWidth;
      window.innerWidth = 400;
      try {
        view();
        const section = entriesSection();
        expect(within(section).queryByRole("table")).toBeNull();
        const details = section.querySelector("details") as HTMLDetailsElement;
        details.open = true;
        fireEvent(details, new Event("toggle"));
        expect(
          within(section).getByRole("button", { name: "Correct" }),
        ).toBeTruthy();
      } finally {
        window.innerWidth = width;
      }
    });
  });

  it("puts the comments column before the other answers", () => {
    state.entries = [
      entry("a", "2027test_qm1", {
        teleopFuelScored: 10,
        dieCard: true,
        comments: "Tipped over",
      }),
    ];
    view();
    const headers = within(entriesSection())
      .getAllByRole("columnheader")
      .map((h) => h.textContent);
    expect(headers.slice(0, 3)).toEqual([
      "Match",
      "Cards and deaths",
      "Comments",
    ]);
    expect(headers).toContain("Scout");
    expect(headers).not.toContain("Scouter Name");
    expect(headers).not.toContain("Team Number");
  });

  it("shows the pit entry, prescout entries and T-REx reports", async () => {
    const pit: PitEntry = {
      id: "p",
      teamNumber: 1111,
      eventKey: "2027test",
      fieldValues: { drivetrainType: "swerve", trenchFit: true },
      authorUid: "u2",
      scoutName: "Scout B",
      updatedAt: "2027-03-01T09:00:00.000Z",
      photoKeys: ["a", "b"],
    };
    const prescout: PrescoutEntry = {
      id: "q",
      teamNumber: 1111,
      eventKey: "2026xyz",
      fieldValues: {
        watchedEvent: "2026xyz",
        matchType: "qual",
        matchNumber: "4",
        teleopFuelScored: 12,
        comments: "Fast cycles",
        videoUrl: "https://example.com/v",
      },
      authorUid: "u3",
      scoutName: "Scout C",
      updatedAt: "2027-02-01T09:00:00.000Z",
    };
    const trex: TrexReport = {
      id: "t",
      trait: "defense",
      teamNumber: 1111,
      matchNumber: 5,
      eventName: "Test Regional",
      eventKey: "2027test",
      report: "Pins for too long",
      rating: null,
      scoutName: "Scout D",
      updatedAt: "2027-03-01T11:00:00.000Z",
    };
    state.pit = [pit, { ...pit, id: "other", teamNumber: 2222 }];
    state.prescout = [prescout];
    state.trex = [trex, { ...trex, id: "old", eventKey: "2026xyz" }];
    view();
    expect(screen.queryByText("No pit entry yet.")).toBeNull();
    expect(screen.getByText("Can they fit under the trench?")).toBeTruthy();
    expect(screen.getByText("Yes")).toBeTruthy();
    expect(
      await screen.findAllByRole("button", { name: /View photo/ }),
    ).toHaveLength(2);
    const trexSection = screen
      .getByRole("heading", { name: "T-REx traits" })
      .closest("section") as HTMLElement;
    expect(within(trexSection).getAllByText("Pins for too long")).toHaveLength(
      1,
    );
    const notes = comments();
    expect(within(notes).getAllByText("Pins for too long")).toHaveLength(1);
    expect(within(notes).getByText("T-REx")).toBeTruthy();
    expect(within(notes).getByText("Fast cycles")).toBeTruthy();
    expect(within(notes).getByText("Prescout")).toBeTruthy();
    expect(screen.getByText("Q4, 2026xyz")).toBeTruthy();
    expect(
      screen
        .getByRole("link", { name: "Watch the video" })
        .getAttribute("href"),
    ).toBe("https://example.com/v");
  });

  it("shows photos from older entries for the team too, once each", async () => {
    const entry = (id: string, updatedAt: string, photoKeys: string[]) => ({
      id,
      teamNumber: 1111,
      eventKey: "2027test",
      fieldValues: { drivetrainType: "swerve" },
      authorUid: "u2",
      scoutName: "Scout B",
      updatedAt,
      photoKeys,
    });
    state.pit = [
      entry("older", "2027-02-01T09:00:00.000Z", ["a", "b"]),
      entry("newest", "2027-03-01T09:00:00.000Z", ["b", "c"]),
    ];
    view();
    expect(
      await screen.findAllByRole("button", { name: /View photo/ }),
    ).toHaveLength(3);
  });

  it("shows the average rating and count per trait, and nothing when unrated", () => {
    const trex = (id: string, trait: string, rating: number | null) => ({
      id,
      trait,
      teamNumber: 1111,
      matchNumber: 5,
      eventName: "Test Regional",
      eventKey: "2027test",
      report: `Note ${id}`,
      rating,
      scoutName: "Scout D",
      updatedAt: "2027-03-01T11:00:00.000Z",
    });
    state.trex = [trex("a", "defense", null)];
    view();
    expect(screen.queryByLabelText("Average ratings")).toBeNull();
    cleanup();
    state.trex = [
      trex("a", "defense", 5),
      trex("b", "defense", 4),
      trex("c", "defense", 4),
      trex("d", "defense", 4),
      trex("e", "defense", 4),
      trex("f", "fuelScoring", 3),
      trex("g", "autonomous", null),
    ];
    view();
    const list = screen.getByLabelText("Average ratings");
    expect(list.textContent).toContain("Defense: 4.2 from 5 ratings");
    expect(list.textContent).toContain("Fuel scoring: 3.0 from 1 rating");
    expect(list.textContent).not.toContain("Autonomous");
    expect(screen.getAllByText(/Rating 4 of 5/).length).toBeGreaterThan(0);
  });

  it("asks for sign-in and does not claim data when signed out", () => {
    state.signedIn = false;
    view();
    expect(
      screen.getByText("Sign in to load scouting data for this team."),
    ).toBeTruthy();
  });

  it("says so when the path is not a team number", () => {
    view("/teams/abc");
    expect(screen.getByText("That is not a team number.")).toBeTruthy();
  });
  describe("pick list control", () => {
    const list = (over: Partial<PickList> = {}): PickList => ({
      id: "l1",
      name: "Main list",
      teamNumbers: [3333, 1111],
      tiers: [
        { name: "1st pick", teams: [3333] },
        { name: "2nd pick", teams: [1111] },
      ],
      dnp: [],
      authorUid: "u1",
      authorDisplayName: "Lead A",
      updatedMs: 2_000,
      ...over,
    });

    it("points to the Picks tab when no list exists", () => {
      view();
      const link = screen.getByRole("link", { name: "Create one on Picks." });
      expect(link.getAttribute("href")).toBe("/picks");
    });

    it("shows the team's tier and place on the newest list", () => {
      state.lists = [
        list({ id: "old", name: "Old list", updatedMs: 1_000 }),
        list(),
      ];
      view();
      expect(
        screen.getByText("Tier 2 (2nd pick), #2 on Main list"),
      ).toBeTruthy();
    });

    it("adds the team to a chosen tier through the shared save", () => {
      state.lists = [
        list({
          teamNumbers: [3333],
          tiers: [
            { name: "1st pick", teams: [3333] },
            { name: "2nd pick", teams: [] },
          ],
        }),
      ];
      view();
      expect(screen.getByText("Not on Main list")).toBeTruthy();
      fireEvent.click(screen.getByRole("button", { name: "Pick list" }));
      fireEvent.change(screen.getByLabelText("Tier"), {
        target: { value: "1" },
      });
      fireEvent.click(screen.getByRole("button", { name: "Add to list" }));
      const [saved, label] = state.save.mock.calls[0] as [PickList, string];
      expect(label).toBe("Pick list Main list");
      expect(saved.tiers[1]?.teams).toEqual([1111]);
      expect(saved.teamNumbers).toEqual([3333, 1111]);
      expect(saved.updatedMs).toBeGreaterThanOrEqual(2_000);
    });

    it("needs a reason for do not pick, then saves it", () => {
      state.lists = [list()];
      view();
      fireEvent.click(screen.getByRole("button", { name: "Pick list" }));
      fireEvent.click(screen.getByRole("button", { name: "Do not pick" }));
      expect(screen.getByRole("alert").textContent).toContain("Say why");
      expect(state.save).not.toHaveBeenCalled();
      fireEvent.change(screen.getByLabelText("Reason to not pick"), {
        target: { value: "Tips over" },
      });
      fireEvent.click(screen.getByRole("button", { name: "Do not pick" }));
      const [saved] = state.save.mock.calls[0] as [PickList];
      expect(saved.dnp).toEqual([{ team: 1111, reason: "Tips over" }]);
      expect(saved.teamNumbers).toEqual([3333]);
    });

    it("shows a do-not-pick reason and removes the team", () => {
      state.lists = [
        list({
          teamNumbers: [3333],
          tiers: [{ name: "1st pick", teams: [3333] }],
          dnp: [{ team: 1111, reason: "Tips over" }],
        }),
      ];
      view();
      expect(
        screen.getByText("Do not pick: Tips over (Main list)"),
      ).toBeTruthy();
      fireEvent.click(screen.getByRole("button", { name: "Pick list" }));
      fireEvent.click(
        screen.getByRole("button", { name: "Remove from Main list" }),
      );
      const [saved] = state.save.mock.calls[0] as [PickList];
      expect(saved.dnp).toEqual([]);
    });

    it("cannot edit while signed out", () => {
      state.signedIn = false;
      state.lists = [list()];
      view();
      expect(
        (screen.getByRole("button", { name: "Pick list" }) as HTMLButtonElement)
          .disabled,
      ).toBe(true);
    });
  });

  describe("match filter and counts", () => {
    const fuel = (id: string, n: number, fuelScored: number, extra = {}) =>
      entry(id, `2027test_qm${n}`, { teleopFuelScored: fuelScored, ...extra });

    it("limits stats to the last matches and says so", () => {
      state.entries = [
        fuel("a", 1, 10),
        fuel("b", 2, 20),
        fuel("c", 3, 30),
        fuel("d", 4, 40),
      ];
      view();
      const table = () =>
        screen.getByRole("table", { name: "Team 1111 scouted stats" });
      expect(
        within(
          within(table()).getByRole("row", { name: /Fuel Scored/ }),
        ).getAllByRole("cell")[0]?.textContent,
      ).toBe("25±6.5");
      expect(screen.getByText("Showing all 4 scouted matches.")).toBeTruthy();

      fireEvent.click(screen.getByRole("button", { name: "Last 3" }));
      expect(
        screen
          .getByRole("button", { name: "Last 3" })
          .getAttribute("aria-pressed"),
      ).toBe("true");
      expect(screen.getByText(/Showing the last 3 of 4/)).toBeTruthy();
      expect(
        within(
          within(table()).getByRole("row", { name: /Fuel Scored/ }),
        ).getAllByRole("cell")[0]?.textContent,
      ).toBe("30±5.8");
      expect(
        screen.getByText(
          "3 matches scouted. A match with several scouts counts once.",
        ),
      ).toBeTruthy();
    });

    it("shows start position counts from the config field", () => {
      state.entries = [
        fuel("a", 1, 1, { starting: "Center Hub" }),
        fuel("b", 2, 1, { starting: "Center Hub" }),
        fuel("c", 3, 1, { starting: "Depot Bump" }),
      ];
      view();
      const stats = screen
        .getByRole("heading", { name: "Event stats" })
        .closest("section") as HTMLElement;
      expect(within(stats).getByText("Robot Starting Position")).toBeTruthy();
      expect(screen.getByText("Center Hub 2, Depot Bump 1")).toBeTruthy();
    });

    it("hides the filter when there are no scouted matches", () => {
      view();
      expect(screen.queryByText("Matches used")).toBeNull();
    });
  });
});

describe("team page for a mentor", () => {
  beforeEach(() => setRoles(ready("mentor")));

  it("has no Pre-scout link, since a mentor writes nothing", () => {
    view();
    expect(screen.queryByRole("link", { name: "Pre-scout" })).toBeNull();
  });

  it("reads the strategy note and has nowhere to type", () => {
    state.notes = [
      {
        id: "2027test_1111",
        eventKey: "2027test",
        teamNumber: 1111,
        text: "Defends the ramp",
        authorUid: "u2",
        authorDisplayName: "Lead B",
        updatedMs: Date.parse("2027-03-01T10:00:00Z"),
      },
    ];
    view();
    expect(screen.getByText("Defends the ramp")).toBeTruthy();
    expect(screen.queryByRole("textbox")).toBeNull();
  });

  it("shows the pick list place with no way to change it", () => {
    state.lists = [
      {
        id: "l1",
        name: "Main list",
        teamNumbers: [3333, 1111],
        tiers: [
          { name: "1st pick", teams: [3333] },
          { name: "2nd pick", teams: [1111] },
        ],
        dnp: [],
        authorUid: "u1",
        authorDisplayName: "Lead A",
        updatedMs: 2_000,
      } satisfies PickList,
    ];
    view();
    expect(screen.getByText("Tier 2 (2nd pick), #2 on Main list")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Pick list" })).toBeNull();
  });

  it("does not point to a page that creates a list", () => {
    view();
    expect(screen.getByText(/No pick lists yet/)).toBeTruthy();
    expect(screen.queryByRole("link", { name: /Create one/ })).toBeNull();
  });

  it("gives no Correct button on a scout entry", () => {
    state.entries = [entry("a", "2027test_qm1", { teleopFuelScored: 10 })];
    view();
    const section = entriesSection();
    expect(
      within(section).queryByRole("button", { name: /Correct/ }),
    ).toBeNull();
    expect(within(section).getByText("10")).toBeTruthy();
  });
});
