// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { bundledConfig } from "../data/formConfig";
import type { PitEntry } from "../data/parse";
import type { OutboxItem } from "../outbox/outbox";
import { net, resetQueue } from "../photos/fakeService";
import { waitingText } from "../photos/state";
import { allFields } from "../scout/config";
import { PitFormRoute, PitListRoute } from "./PitScreens";

const mocks = vi.hoisted(() => ({
  auth: {
    status: "signed-in",
    uid: "uid-1" as string | null,
    displayName: "Scout A",
  },
  entries: [] as unknown[],
  ready: true,
  outbox: [] as unknown[],
  enqueue: vi.fn(),
  merge: vi.fn(),
}));

const stored = vi.hoisted(() => ({ value: true }));
vi.mock("../outbox/settled", () => ({
  whenInDatabase: () => Promise.resolve(stored.value),
}));
vi.mock("../auth/AuthProvider", () => ({ useAuth: () => mocks.auth }));
vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => mocks.outbox }));
vi.mock("../outbox/outbox", () => ({
  enqueueWrite: mocks.enqueue,
  enqueueMerge: mocks.merge,
  getOutbox: () => [],
  subscribeOutbox: () => () => undefined,
}));
vi.mock("../photos/service", () => import("../photos/fakeService"));
vi.mock("../photos/compress", () => ({
  preparePhoto: vi.fn(async (file: File) => file),
}));
vi.mock("../data/useTbaEvent", () => ({
  useTbaEvent: () => ({
    eventKey: "2027test",
    status: "ready",
    teams: [
      { number: 1111, nickname: "Alpha" },
      { number: 2222, nickname: "Beta" },
      { number: 3333, nickname: "Gamma" },
    ],
  }),
}));
vi.mock("../data/useCollections", async () => {
  const { bundledConfig } = await import("../data/formConfig");
  return {
    useFormConfig: () => bundledConfig.pit,
    usePitEntries: () => ({
      items: mocks.entries,
      ready: mocks.ready,
      failed: false,
    }),
  };
});

function entry(over: Partial<PitEntry> & { id: string }): PitEntry {
  return {
    teamNumber: 1111,
    eventKey: "2027test",
    fieldValues: {},
    authorUid: "uid-1",
    scoutName: "Scout A",
    updatedAt: "2027-03-05T18:00:00.000Z",
    photoKeys: [],
    ...over,
  };
}

const scouted = { fieldValues: { swerveGearRatio: "6.75" }, photoKeys: ["k1"] };

function renderAt(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/scout/pit" element={<PitListRoute />} />
        <Route path="/scout/pit/:team" element={<PitFormRoute />} />
        <Route path="/scout/pit/:team/:id" element={<PitFormRoute />} />
      </Routes>
    </MemoryRouter>,
  );
}

beforeEach(async () => {
  localStorage.clear();
  await resetQueue();
  URL.createObjectURL = vi.fn(() => "blob:local");
  URL.revokeObjectURL = vi.fn();
  setRoles(ready("scouter"));
  mocks.auth.status = "signed-in";
  mocks.auth.uid = "uid-1";
  mocks.entries = [];
  mocks.ready = true;
  mocks.outbox = [];
  for (const write of [mocks.enqueue, mocks.merge]) {
    write.mockReset();
    write.mockImplementation(async (path: string) => {
      (mocks.outbox as OutboxItem[]).unshift({
        id: "o1",
        path,
        data: {},
        label: "",
        createdAt: "",
        status: "sending",
      });
    });
  }
});
afterEach(cleanup);

describe("pit list", () => {
  it("counts the teams done and lists the others first", () => {
    mocks.entries = [entry({ id: "e1", ...scouted })];
    renderAt("/scout/pit");
    expect(screen.getByText("1 of 3 done")).toBeTruthy();
    expect(screen.queryByText("1111")).toBeNull();
    expect(screen.getByText("2222")).toBeTruthy();
    expect(screen.getByText("3333")).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "All (3)" }));
    expect(screen.getByText("1111")).toBeTruthy();
    expect(screen.getByText("Done")).toBeTruthy();
  });

  it("says what is missing for a team with only a form or only a photo", () => {
    mocks.entries = [
      entry({ id: "e1", fieldValues: scouted.fieldValues }),
      entry({ id: "e2", teamNumber: 2222, photoKeys: ["k2"] }),
    ];
    renderAt("/scout/pit");
    expect(screen.getByText("0 of 3 done")).toBeTruthy();
    expect(screen.getByText("Form done, no photo")).toBeTruthy();
    expect(screen.getByText("Photo, no form")).toBeTruthy();
    expect(screen.getByText("Not done")).toBeTruthy();
  });

  it("counts a form and a photo on two entries for the team as done", () => {
    mocks.entries = [
      entry({ id: "e1", fieldValues: scouted.fieldValues }),
      entry({ id: "e2", authorUid: "uid-2", photoKeys: ["k2"] }),
    ];
    renderAt("/scout/pit");
    expect(screen.getByText("1 of 3 done")).toBeTruthy();
  });

  it("links a team number to the Team page for a lead only", () => {
    renderAt("/scout/pit");
    expect(screen.queryByRole("link", { name: "2222" })).toBeNull();
    cleanup();
    setRoles(ready("admin"));
    renderAt("/scout/pit");
    expect(
      screen.getByRole("link", { name: "2222" }).getAttribute("href"),
    ).toBe("/teams/2222");
  });

  it("does not count an entry from another event", () => {
    mocks.entries = [entry({ id: "e1", eventKey: "2026other", ...scouted })];
    renderAt("/scout/pit");
    expect(screen.getByText("0 of 3 done")).toBeTruthy();
  });

  it("waits for the entries before it counts", () => {
    mocks.ready = false;
    renderAt("/scout/pit");
    expect(screen.getByText("Loading the pit entries.")).toBeTruthy();
    expect(screen.queryByText(/of 3 done/)).toBeNull();
  });

  it("switches between the scouting screens", () => {
    renderAt("/scout/pit");
    const tabs = screen.getByRole("navigation", { name: "Scouting form" });
    expect(
      [...tabs.querySelectorAll("a")].map((a) => a.getAttribute("href")),
    ).toEqual([
      "/scout",
      "/scout/pit",
      "/scout/prescout",
      "/scout/shifts",
      "/scout/trex",
    ]);
    expect(
      screen.getByRole("link", { name: "Pit" }).getAttribute("aria-current"),
    ).toBe("page");
  });

  it("opens a team that is not on the list", () => {
    renderAt("/scout/pit");
    fireEvent.change(screen.getByLabelText("Open a team by number"), {
      target: { value: "4444" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Open" }));
    expect(screen.getByRole("heading", { name: "Team 4444" })).toBeTruthy();
  });
});

describe("pit form", () => {
  it("saves a new entry through the outbox and shows its delivery", async () => {
    renderAt("/scout/pit/2222");
    expect(screen.getByRole("heading", { name: "Team 2222" })).toBeTruthy();
    expect(screen.getByText("New entry")).toBeTruthy();
    expect(screen.getByRole("heading", { name: "Photos" })).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 2222 saved" });
    expect(mocks.enqueue).toHaveBeenCalledTimes(1);
    const [path, doc] = mocks.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(path).toBe(`pitScoutEntries/${doc.id}`);
    expect(doc).toMatchObject({
      teamNumber: 2222,
      eventKey: "2027test",
      authorUid: "uid-1",
      authorDisplayName: "Scout A",
      photoKeys: [],
    });
    expect(screen.getByText("Sending")).toBeTruthy();
  });

  it("opens the scout's own saved entry and merges only the answers", async () => {
    const field = allFields(bundledConfig.pit).find(
      (f) => f.code === "swerveGearRatio",
    );
    mocks.entries = [
      entry({
        id: "e1",
        fieldValues: { swerveGearRatio: "6.75" },
        photoKeys: ["key-a"],
        scoutName: "Old Name",
      }),
    ];
    renderAt("/scout/pit/1111");
    await screen.findByText("Editing your saved entry");
    const input = screen.getByLabelText(field?.title ?? "") as HTMLInputElement;
    expect(input.value).toBe("6.75");
    fireEvent.change(input, { target: { value: "7.5" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 1111 saved" });
    expect(mocks.enqueue).not.toHaveBeenCalled();
    const [path, doc] = mocks.merge.mock.calls[0] as [
      string,
      Record<string, Record<string, unknown>>,
    ];
    expect(path).toBe("pitScoutEntries/e1");
    expect(Object.keys(doc).sort()).toEqual([
      "fieldValues",
      "updatedAt",
      "updatedAtTs",
    ]);
    expect(doc.fieldValues?.swerveGearRatio).toBe("7.5");
  });

  it("never stamps a merge earlier than the entry's stored stamp", async () => {
    const ahead = Date.now() + 120_000;
    mocks.entries = [entry({ id: "e1", stampMs: ahead })];
    renderAt("/scout/pit/1111");
    await screen.findByText("Editing your saved entry");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 1111 saved" });
    const [, doc] = mocks.merge.mock.calls[0] as [
      string,
      { updatedAtTs: { toMillis(): number } },
    ];
    expect(doc.updatedAtTs.toMillis()).toBe(ahead);
  });

  it("adds a picked photo to the entry without saving the form", async () => {
    net.attach.mockImplementation(async (_id, keys) => keys);
    mocks.entries = [entry({ id: "e1", photoKeys: ["key-a"] })];
    renderAt("/scout/pit/1111");
    await screen.findByText("Editing your saved entry");
    await screen.findByRole("button", { name: "View photo 1" });
    const input = document.querySelector("input[multiple]") as HTMLInputElement;
    fireEvent.change(input, {
      target: { files: [new File(["x"], "robot.jpg", { type: "image/jpeg" })] },
    });
    await waitFor(() =>
      expect(net.attach).toHaveBeenCalledWith("e1", ["new-key.jpg"]),
    );
    expect(mocks.enqueue).not.toHaveBeenCalled();
    expect(mocks.merge).not.toHaveBeenCalled();
  });

  it("puts photos on a teammate's entry and lets the scout take them off", async () => {
    mocks.entries = [
      entry({
        id: "theirs",
        authorUid: "uid-2",
        scoutName: "Scout B",
        photoKeys: ["key-b"],
      }),
    ];
    renderAt("/scout/pit/1111");
    await screen.findByRole("button", { name: "View photo 1" });
    const input = document.querySelector("input[multiple]") as HTMLInputElement;
    fireEvent.change(input, {
      target: { files: [new File(["x"], "robot.jpg", { type: "image/jpeg" })] },
    });
    await waitFor(() =>
      expect(net.attach).toHaveBeenCalledWith("theirs", ["new-key.jpg"]),
    );
    fireEvent.click(screen.getByRole("button", { name: "Remove photo 1" }));
    fireEvent.click(screen.getByRole("button", { name: "Remove" }));
    await waitFor(() =>
      expect(net.detach).toHaveBeenCalledWith("theirs", "key-b"),
    );
    await waitFor(() => expect(net.remove).toHaveBeenCalledWith("key-b"));
  });

  it("holds a photo until the team has an entry and says so", async () => {
    renderAt("/scout/pit/2222");
    const input = document.querySelector("input[multiple]") as HTMLInputElement;
    fireEvent.change(input, {
      target: { files: [new File(["x"], "robot.jpg", { type: "image/jpeg" })] },
    });
    await screen.findByText(waitingText);
    await screen.findByText("Uploaded");
    expect(net.attach).not.toHaveBeenCalled();
  });

  it("saves a new entry with no photo keys while a photo is still uploading", async () => {
    net.upload.mockResolvedValue({ type: "unavailable", reason: "offline" });
    renderAt("/scout/pit/2222");
    const input = document.querySelector("input[multiple]") as HTMLInputElement;
    fireEvent.change(input, {
      target: { files: [new File(["x"], "robot.jpg", { type: "image/jpeg" })] },
    });
    await screen.findByText("Waiting for a connection");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 2222 saved" });
    const [, doc] = mocks.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(doc.photoKeys).toEqual([]);
    expect(screen.getByRole("status").textContent).toContain(
      "1 photo still to upload",
    );
  });

  it("merges a second save of an entry created in the same visit", async () => {
    renderAt("/scout/pit/2222");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 2222 saved" });
    fireEvent.click(screen.getByRole("button", { name: "Edit this entry" }));
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() => expect(mocks.merge).toHaveBeenCalledTimes(1));
    const [path] = mocks.enqueue.mock.calls[0] as [string];
    expect(mocks.merge.mock.calls[0]?.[0]).toBe(path);
    expect(mocks.enqueue).toHaveBeenCalledTimes(1);
  });

  it("takes a removed photo off the entry at once, without a save", async () => {
    mocks.entries = [entry({ id: "e1", photoKeys: ["key-a", "key-b"] })];
    renderAt("/scout/pit/1111");
    await screen.findByRole("button", { name: "View photo 2" });
    fireEvent.click(screen.getByRole("button", { name: "Remove photo 1" }));
    fireEvent.click(screen.getByRole("button", { name: "Remove" }));
    await waitFor(() => expect(net.detach).toHaveBeenCalledWith("e1", "key-a"));
    await waitFor(() => expect(net.remove).toHaveBeenCalledWith("key-a"));
    expect(mocks.merge).not.toHaveBeenCalled();
  });

  it("keeps another scout's entry and files a separate one", async () => {
    mocks.entries = [
      entry({ id: "theirs", authorUid: "uid-2", scoutName: "Scout B" }),
    ];
    renderAt("/scout/pit/1111");
    expect(screen.getByText("New entry")).toBeTruthy();
    expect(screen.getByText(/Also scouted by Scout B/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 1111 saved" });
    const [path] = mocks.enqueue.mock.calls[0] as [string];
    expect(path).not.toBe("pitScoutEntries/theirs");
  });

  it("lets a lead correct another scout's entry and leaves its author and photos", async () => {
    setRoles(ready("developer"));
    mocks.entries = [
      entry({
        id: "theirs",
        authorUid: "uid-2",
        scoutName: "Scout B",
        eventKey: "",
        photoKeys: ["key-b"],
      }),
    ];
    renderAt("/scout/pit/1111");
    expect(screen.getByText("New entry")).toBeTruthy();
    fireEvent.click(screen.getByRole("link", { name: "Edit Scout B's entry" }));
    await screen.findByText("Editing Scout B's entry");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 1111 saved" });
    const [path, doc] = mocks.merge.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(path).toBe("pitScoutEntries/theirs");
    expect(Object.keys(doc).sort()).toEqual([
      "fieldValues",
      "updatedAt",
      "updatedAtTs",
    ]);
  });

  it("does not let a scout open another scout's entry", async () => {
    mocks.entries = [
      entry({ id: "theirs", authorUid: "uid-2", scoutName: "Scout B" }),
    ];
    renderAt("/scout/pit/1111/theirs");
    await screen.findByText(/Only Scout B or a lead can change/);
    expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
  });

  it("says when an entry does not exist", async () => {
    renderAt("/scout/pit/1111/nope");
    await screen.findByText("That entry was not found.");
  });

  it("stamps the active event on a new entry and counts an entry with none", async () => {
    mocks.entries = [
      entry({ id: "old", teamNumber: 1111, eventKey: "", ...scouted }),
    ];
    renderAt("/scout/pit");
    expect(screen.getByText("1 of 3 done")).toBeTruthy();
    cleanup();
    renderAt("/scout/pit/2222");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await screen.findByRole("heading", { name: "Team 2222 saved" });
    const [, doc] = mocks.enqueue.mock.calls[0] as [
      string,
      Record<string, unknown>,
    ];
    expect(doc.eventKey).toBe("2027test");
  });

  it("waits for the entries so a saved one is not filed twice", () => {
    mocks.ready = false;
    renderAt("/scout/pit/1111");
    expect(screen.getByText("Loading the saved answers.")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
  });

  it("needs a signed-in scout to save", () => {
    mocks.auth.status = "signed-out";
    mocks.auth.uid = null;
    renderAt("/scout/pit/1111");
    const save = screen.getByRole("button", {
      name: "Sign in to save",
    }) as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    expect(mocks.enqueue).not.toHaveBeenCalled();
  });

  it("reports a write the outbox could not keep", async () => {
    mocks.enqueue.mockRejectedValue(new Error("storage full"));
    renderAt("/scout/pit/2222");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    await waitFor(() =>
      expect(screen.getByRole("alert").textContent).toContain(
        "Nothing was recorded",
      ),
    );
    expect(
      screen.queryByRole("heading", { name: "Team 2222 saved" }),
    ).toBeNull();
  });

  it("refuses a bad team number", () => {
    renderAt("/scout/pit/abc");
    expect(screen.getByText("That is not a team number.")).toBeTruthy();
  });
});
