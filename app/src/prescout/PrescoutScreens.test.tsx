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
import { ready, setRoles } from "../auth/rolesMock";
import { bundledConfig } from "../data/formConfig";
import type { PrescoutEntry } from "../data/parse";
import type { OutboxItem } from "../outbox/outbox";
import { allFields } from "../scout/config";
import {
  PrescoutFormRoute,
  PrescoutListRoute,
  PrescoutTeamRoute,
} from "./PrescoutScreens";

const mocks = vi.hoisted(() => ({
  plan: {
    status: "none",
    plan: null as unknown,
    saved: false,
  },
  auth: {
    status: "signed-in",
    uid: "uid-1" as string | null,
    displayName: "Scout A",
  },
  eventKey: "2027test",
  entries: [] as unknown[],
  ready: true,
  outbox: [] as unknown[],
  enqueue: vi.fn(),
}));

vi.mock("../auth/AuthProvider", () => ({ useAuth: () => mocks.auth }));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => mocks.outbox }));
vi.mock("../outbox/outbox", () => ({ enqueueWrite: mocks.enqueue }));
vi.mock("./usePrescoutPlan", () => ({ usePrescoutPlan: () => mocks.plan }));
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: mocks.eventKey,
    status: "ready",
    teams: [
      { number: 1111, nickname: "Alpha" },
      { number: 2222, nickname: "Beta" },
    ],
  }),
}));
vi.mock("../data/useCollections", async () => {
  const { bundledConfig } = await import("../data/formConfig");
  return {
    useFormConfig: () => bundledConfig.prescout,
    usePrescoutEntries: () => ({
      items: mocks.entries,
      ready: mocks.ready,
      failed: false,
    }),
  };
});

function record(id: string, over: Partial<PrescoutEntry> = {}): PrescoutEntry {
  return {
    id,
    teamNumber: 1111,
    eventKey: "2027test",
    fieldValues: {
      watchedEvent: "2026txhou",
      matchType: "qual",
      matchNumber: id,
    },
    authorUid: "uid-1",
    scoutName: "Scout A",
    updatedAt: `2027-03-05T18:00:0${id}.000Z`,
    ...over,
  };
}

function renderAt(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/scout/prescout" element={<PrescoutListRoute />} />
        <Route path="/scout/prescout/:team" element={<PrescoutTeamRoute />} />
        <Route
          path="/scout/prescout/:team/:id"
          element={<PrescoutFormRoute />}
        />
      </Routes>
    </MemoryRouter>,
  );
}

const title = (code: string) =>
  allFields(bundledConfig.prescout).find((f) => f.code === code)?.title ?? "";

beforeEach(() => {
  localStorage.clear();
  setRoles(ready("scouter"));
  mocks.auth.status = "signed-in";
  mocks.auth.uid = "uid-1";
  mocks.eventKey = "2027test";
  mocks.entries = [];
  mocks.ready = true;
  mocks.outbox = [];
  mocks.plan = { status: "none", plan: null, saved: false };
  mocks.enqueue.mockReset();
  mocks.enqueue.mockImplementation(async (path: string) => {
    (mocks.outbox as OutboxItem[]).unshift({
      id: "o1",
      path,
      data: {},
      label: "",
      createdAt: "",
      status: "sending",
    });
  });
});
afterEach(cleanup);

describe("prescout list", () => {
  it("shows records per team and counts the teams with all five", () => {
    mocks.entries = [1, 2, 3, 4, 5].map((n) => record(String(n)));
    renderAt("/scout/prescout");
    expect(screen.getByText("1 of 2 teams done")).toBeTruthy();
    expect(screen.queryByText("1111")).toBeNull();
    expect(screen.getByText("2222")).toBeTruthy();
    expect(screen.getByText("0 of 5")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "All (2)" }));
    expect(screen.getByText("5 of 5")).toBeTruthy();
    expect(screen.getByText("Started by Scout A")).toBeTruthy();
  });

  it("links a team number to the Team page for a lead only", () => {
    renderAt("/scout/prescout");
    fireEvent.click(screen.getByRole("button", { name: /^All/ }));
    expect(screen.queryByRole("link", { name: "1111" })).toBeNull();
    cleanup();
    setRoles(ready("strategy"));
    renderAt("/scout/prescout");
    fireEvent.click(screen.getByRole("button", { name: /^All/ }));
    expect(
      screen.getByRole("link", { name: "1111" }).getAttribute("href"),
    ).toBe("/teams/1111");
  });
});

describe("prescout team", () => {
  it("offers a lead Edit on a teammate's record and a scout View", () => {
    mocks.entries = [record("1", { authorUid: "uid-2", scoutName: "Scout B" })];
    renderAt("/scout/prescout/1111");
    expect(screen.getByRole("link", { name: "View" })).toBeTruthy();
    cleanup();
    setRoles(ready("admin"));
    renderAt("/scout/prescout/1111");
    expect(screen.getByRole("link", { name: "Edit" })).toBeTruthy();
  });

  it("lists the records and offers to add one", () => {
    mocks.entries = [
      record("1"),
      record("2", { authorUid: "uid-2", scoutName: "Scout B" }),
    ];
    renderAt("/scout/prescout/1111");
    expect(screen.getByText("2 of 5 records")).toBeTruthy();
    expect(screen.getByText("Q1")).toBeTruthy();
    expect(screen.getByRole("link", { name: "Edit" })).toBeTruthy();
    expect(screen.getByRole("link", { name: "View" })).toBeTruthy();
    expect(
      screen.getByRole("link", { name: "Add record" }).getAttribute("href"),
    ).toBe("/scout/prescout/1111/new");
  });

  it("stops at five records", () => {
    mocks.entries = [1, 2, 3, 4, 5].map((n) => record(String(n)));
    renderAt("/scout/prescout/1111");
    expect(screen.queryByRole("link", { name: "Add record" })).toBeNull();
    expect(screen.getByText("Team 1111 has all 5 records.")).toBeTruthy();
  });
});

describe("prescout form", () => {
  it("asks before it saves a record with required answers missing", async () => {
    renderAt("/scout/prescout/1111/new");
    expect(screen.getByText("Record 1 of 5")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    const alert = screen.getByText("Required, still empty:").closest("div");
    expect(
      within(alert as HTMLElement).getByText(title("matchNumber")),
    ).toBeTruthy();
    expect(mocks.enqueue).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole("button", { name: "Save anyway" }));
    await screen.findByRole("heading", { name: "Team 1111 record saved" });
    const [path, doc] = mocks.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(path).toBe(`prescoutEntries/${doc.id}`);
    expect(doc).toMatchObject({
      teamNumber: 1111,
      eventKey: "2027test",
      authorUid: "uid-1",
    });
    expect("photoKeys" in doc).toBe(false);
  });

  it("refuses a second record for the same match", async () => {
    mocks.entries = [
      record("1", {
        fieldValues: {
          watchedEvent: "2026txhou",
          matchType: "qual",
          matchNumber: "16",
        },
      }),
    ];
    renderAt("/scout/prescout/1111/new");
    fireEvent.change(screen.getByLabelText(title("watchedEvent")), {
      target: { value: "2026txhou" },
    });
    fireEvent.change(screen.getByLabelText(title("matchNumber")), {
      target: { value: "16" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(screen.getByRole("alert").textContent).toBe(
      "Team 1111 already has a record for Q16 at 2026txhou.",
    );
    expect(mocks.enqueue).not.toHaveBeenCalled();
  });

  it("opens the scout's own record and updates it in place", async () => {
    mocks.entries = [
      record("1", {
        eventKey: "2026other",
        fieldValues: { watchedEvent: "e", matchType: "qual", matchNumber: "3" },
      }),
    ];
    renderAt("/scout/prescout/1111/1");
    await screen.findByText("Editing your record");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 1111 record saved" });
    const [path, doc] = mocks.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(path).toBe("prescoutEntries/1");
    expect(doc.eventKey).toBe("2026other");
  });

  it("shows a teammate's record read only", () => {
    mocks.entries = [record("1", { authorUid: "uid-2", scoutName: "Scout B" })];
    renderAt("/scout/prescout/1111/1");
    expect(screen.getByText(/Recorded by Scout B/)).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
  });

  it("lets a lead correct a teammate's record and keeps its author", async () => {
    setRoles(ready("strategy"));
    mocks.entries = [record("1", { authorUid: "uid-2", scoutName: "Scout B" })];
    renderAt("/scout/prescout/1111/1");
    await screen.findByText("Editing Scout B's record");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 1111 record saved" });
    const [path, doc] = mocks.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(path).toBe("prescoutEntries/1");
    expect(doc).toMatchObject({
      authorUid: "uid-2",
      authorDisplayName: "Scout B",
    });
  });

  it("explains a full team and a missing event", () => {
    mocks.entries = [1, 2, 3, 4, 5].map((n) => record(String(n)));
    renderAt("/scout/prescout/1111/new");
    expect(
      screen.getByText("Team 1111 already has all 5 records."),
    ).toBeTruthy();
    cleanup();
    mocks.entries = [];
    mocks.eventKey = "";
    renderAt("/scout/prescout/1111/new");
    expect(screen.getByText(/No event is set/)).toBeTruthy();
  });

  it("says when a record does not exist", () => {
    renderAt("/scout/prescout/1111/nope");
    expect(screen.getByText("That record was not found.")).toBeTruthy();
  });
});

describe("prescout match picker and film", () => {
  const match = (n: string, over: Record<string, unknown> = {}) => ({
    matchKey: `2026txhou_qm${n}`,
    eventKey: "2026txhou",
    eventName: "Houston",
    matchType: "qual",
    number: n,
    isPlayoff: false,
    videoUrl: `https://www.youtube.com/watch?v=abcdefghij${n}&t=20`,
    ...over,
  });

  beforeEach(() => {
    mocks.plan = {
      status: "ready",
      saved: false,
      plan: {
        fetchedAt: "2027-03-05T18:00:00.000Z",
        note: null,
        matches: [match("1"), match("2")],
      },
    };
  });

  it("starts a new record on the first match and plays its film", () => {
    renderAt("/scout/prescout/1111/new");
    expect(
      screen.getByRole("button", { name: "Q1", pressed: true }),
    ).toBeTruthy();
    expect(
      (screen.getByLabelText(title("matchNumber")) as HTMLInputElement).value,
    ).toBe("1");
    const frame = screen.getByTitle("Match video");
    expect(frame.getAttribute("src")).toBe(
      "https://www.youtube-nocookie.com/embed/abcdefghij1?start=20",
    );
    expect(frame.getAttribute("referrerpolicy")).toBeTruthy();
  });

  it("fills the form when another match is picked", () => {
    renderAt("/scout/prescout/1111/new");
    fireEvent.click(screen.getByRole("button", { name: "Q2" }));
    expect(
      (screen.getByLabelText(title("matchNumber")) as HTMLInputElement).value,
    ).toBe("2");
    expect(
      (screen.getByLabelText(title("watchedEvent")) as HTMLInputElement).value,
    ).toBe("Houston");
  });

  it("disables a match the team already has a record for", () => {
    mocks.entries = [
      record("9", {
        fieldValues: {
          watchedEvent: "Houston",
          matchType: "qual",
          matchNumber: "1",
        },
      }),
    ];
    renderAt("/scout/prescout/1111/new");
    expect(
      (screen.getByRole("button", { name: "Q1 (saved)" }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    expect(
      screen.getByRole("button", { name: "Q2", pressed: true }),
    ).toBeTruthy();
  });

  it("opens a non-YouTube link in a new tab instead of embedding it", () => {
    mocks.plan = {
      status: "ready",
      saved: false,
      plan: {
        fetchedAt: "",
        note: null,
        matches: [match("1", { videoUrl: "https://example.com/film" })],
      },
    };
    renderAt("/scout/prescout/1111/new");
    expect(screen.queryByTitle("Match video")).toBeNull();
    const link = screen.getByRole("link", { name: /Open the video/ });
    expect(link.getAttribute("target")).toBe("_blank");
    expect(link.getAttribute("rel")).toContain("noopener");
  });

  it("says so when the lookup failed and nothing is saved", () => {
    mocks.plan = { status: "failed", plan: null, saved: false };
    renderAt("/scout/prescout/1111/new");
    expect(screen.getByText(/Could not reach The Blue Alliance/)).toBeTruthy();
  });

  it("says when it shows the list saved on the device", () => {
    mocks.plan = { ...mocks.plan, saved: true };
    renderAt("/scout/prescout/1111/new");
    expect(screen.getByText(/saved on this device/)).toBeTruthy();
  });
});
