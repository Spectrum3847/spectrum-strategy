// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { parseManaged } from "./profiles";
import { Users } from "./UsersPage";

const state = vi.hoisted(() => ({
  seen: {} as Record<string, unknown>,
  outbox: [] as unknown[],
  online: true,
  save: vi.fn((..._args: unknown[]) => Promise.resolve()),
  dismiss: vi.fn(),
}));

vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../outbox/outbox", () => ({
  dismissItem: (id: string) => state.dismiss(id),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => state.outbox }));
vi.mock("../ui/useOnline", () => ({ useOnline: () => state.online }));
vi.mock("./useProfiles", () => ({
  useProfiles: () => state.seen,
  saveProfileWrites: (...args: unknown[]) => state.save(...args),
}));

const people = [
  parseManaged("u1", {
    uid: "u1",
    displayName: "Admin A",
    email: "admin@example.test",
    roles: ["admin"],
  }),
  parseManaged("u2", {
    uid: "u2",
    displayName: "Scout B",
    email: "b@example.test",
    roles: ["scouter"],
    createdAt: "2027-01-01T00:00:00.000Z",
  }),
  parseManaged("u3", {
    uid: "u3",
    displayName: "Lead C",
    email: "c@example.test",
    roles: ["strategy"],
    linkedEmails: ["c2@example.test"],
  }),
];

type Sent = { uid: string; doc: Record<string, unknown> }[];
const sent = (call: number): Sent =>
  (state.save.mock.calls[call]?.[0] ?? []) as Sent;

function show(over: Record<string, unknown> = {}) {
  state.seen = {
    items: people,
    ready: true,
    failed: false,
    code: null,
    fromCache: false,
    count: people.length,
    ...over,
  };
  render(<Users />);
}

afterEach(() => {
  cleanup();
  state.outbox = [];
  state.online = true;
  state.save.mockClear();
  state.dismiss.mockClear();
  setRoles(ready("admin"));
});

describe("Users", () => {
  it("lists name, email, roles and linked addresses", () => {
    show();
    expect(screen.getByRole("heading", { name: "Users" })).toBeTruthy();
    expect(screen.getByText("Scout B")).toBeTruthy();
    expect(screen.getByText("b@example.test")).toBeTruthy();
    expect(screen.getByText("Roles: Strategist")).toBeTruthy();
    expect(screen.getByText("Also signs in as: c2@example.test")).toBeTruthy();
    expect(screen.getByText("3 users")).toBeTruthy();
  });

  it("says the admin cannot edit their own profile and offers no editor", () => {
    show();
    expect(screen.getByText("You cannot edit your own profile.")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Edit Admin A" })).toBeNull();
    expect(screen.getByRole("button", { name: "Edit Scout B" })).toBeTruthy();
  });

  it("searches by name or email", () => {
    show();
    const box = screen.getByLabelText("Search by name or email");
    fireEvent.change(box, { target: { value: "c@example" } });
    expect(screen.getByText("Lead C")).toBeTruthy();
    expect(screen.queryByText("Scout B")).toBeNull();
    expect(screen.getByText("1 of 3 users")).toBeTruthy();
    fireEvent.change(box, { target: { value: "nobody" } });
    expect(screen.getByText("No user matches that search.")).toBeTruthy();
  });

  it("saves roles through the outbox as the full stored document", async () => {
    show();
    fireEvent.click(screen.getByRole("button", { name: "Edit Scout B" }));
    const save = screen.getByRole("button", { name: "Save roles" });
    expect((save as HTMLButtonElement).disabled).toBe(true);
    fireEvent.click(screen.getByLabelText("Strategist"));
    fireEvent.click(save);
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    const writes = sent(0);
    expect(writes).toHaveLength(1);
    expect(writes[0]?.uid).toBe("u2");
    expect(writes[0]?.doc).toEqual({
      ...people[1]?.raw,
      roles: ["scouter", "strategy"],
    });
    await waitFor(() =>
      expect(screen.queryByRole("button", { name: "Save roles" })).toBeNull(),
    );
  });

  it("assigns the mentor role and keeps the roles already held", async () => {
    show();
    fireEvent.click(screen.getByRole("button", { name: "Edit Scout B" }));
    fireEvent.click(screen.getByLabelText("Mentor"));
    fireEvent.click(screen.getByRole("button", { name: "Save roles" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    expect(sent(0)[0]?.doc).toEqual({
      ...people[1]?.raw,
      roles: ["scouter", "mentor"],
    });
  });

  it("renames and links from the editor", async () => {
    show();
    fireEvent.click(screen.getByRole("button", { name: "Edit Scout B" }));
    fireEvent.change(screen.getByLabelText("Display name"), {
      target: { value: "Scout Bee" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Save name" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(1));
    expect(sent(0)[0]?.doc).toMatchObject({ displayName: "Scout Bee" });

    fireEvent.click(screen.getByRole("button", { name: "Edit Scout B" }));
    const pick = screen.getByLabelText("Link to account");
    expect(within(pick).queryByText(/Admin A/)).toBeNull();
    fireEvent.change(pick, { target: { value: "u3" } });
    fireEvent.click(screen.getByRole("button", { name: "Link" }));
    await waitFor(() => expect(state.save).toHaveBeenCalledTimes(2));
    const linked = sent(1);
    expect(linked.map((w) => w.uid)).toEqual(["u2", "u3"]);
    expect(linked[0]?.doc).toMatchObject({
      canonicalUid: "u3",
      roles: ["strategy"],
    });
    expect(linked[1]?.doc.linkedEmails).toEqual([
      "c2@example.test",
      "b@example.test",
    ]);
  });

  it("shows a refused write with the rules' reason and lets it be dismissed", () => {
    state.outbox = [
      {
        id: "o1",
        path: "userProfiles/u2",
        label: "Roles for Scout B",
        status: "refused",
        error: "Missing or insufficient permissions.",
      },
    ];
    show();
    expect(screen.getByText("Roles for Scout B: Refused")).toBeTruthy();
    expect(
      screen.getByText("Missing or insufficient permissions."),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Dismiss" }));
    expect(state.dismiss).toHaveBeenCalledWith("o1");
  });

  it("shows a write that is only on this device", () => {
    state.outbox = [
      {
        id: "o2",
        path: "userProfiles/u3",
        label: "Name for Lead C",
        status: "on-device",
      },
    ];
    show();
    expect(screen.getByText("Name for Lead C: On this device")).toBeTruthy();
  });

  it("shows an error when the write cannot be queued", async () => {
    state.save.mockRejectedValueOnce(new Error("Training mode sends nothing."));
    show();
    fireEvent.click(screen.getByRole("button", { name: "Edit Scout B" }));
    fireEvent.click(screen.getByLabelText("Developer"));
    fireEvent.click(screen.getByRole("button", { name: "Save roles" }));
    const alert = await screen.findByRole("alert");
    expect(alert.textContent).toContain("Training mode sends nothing.");
  });
});

describe("Users states", () => {
  it("shows loading before the first snapshot", () => {
    show({ ready: false, items: [], count: 0 });
    expect(screen.getByRole("status").textContent).toContain("Loading users");
  });

  it("says a refused read is not allowed", () => {
    show({ failed: true, code: "permission-denied", items: [], count: 0 });
    expect(screen.getByRole("alert").textContent).toContain(
      "Only admin accounts can manage users",
    );
    expect(screen.getByRole("button", { name: "Try again" })).toBeTruthy();
  });

  it("says a failed read could not load, with a retry", () => {
    show({ failed: true, code: "unavailable", items: [], count: 0 });
    expect(screen.getByRole("alert").textContent).toContain(
      "Could not load users",
    );
  });

  it("marks a list served from the device cache while offline", () => {
    state.online = false;
    show({ fromCache: true });
    expect(screen.getByRole("status").textContent).toContain(
      "You are offline. This list is the copy saved on this device",
    );
    expect(screen.getByText("Scout B")).toBeTruthy();
  });

  it("does not call an empty cache an empty list", () => {
    state.online = false;
    show({ fromCache: true, items: [], count: 0 });
    expect(screen.getByRole("status").textContent).toContain(
      "no saved user list",
    );
    expect(screen.queryByText("No users found.")).toBeNull();
  });

  it("says when the server has no users", () => {
    show({ items: [], count: 0 });
    expect(screen.getByText("No users found.")).toBeTruthy();
  });
});
