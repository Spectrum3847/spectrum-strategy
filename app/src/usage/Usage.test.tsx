// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ready, setRoles } from "../auth/rolesMock";
import { sharingStore } from "./prefs";
import { SharePanel } from "./SharePanel";
import { Usage } from "./UsagePage";

vi.mock("../auth/rolesContext", () =>
  import("../auth/rolesMock").then((m) => m.rolesModule),
);
vi.mock("../firebase/client", () => ({ db: {} }));

const fixture = {
  updatedAt: "2027-03-04T05:06:07.000Z",
  windowDays: 30,
  eventsCounted: 12,
  deviceCount: 1,
  tabs: [
    { name: "Scout", count: 8 },
    { name: "Prematch", count: 4 },
  ],
  platforms: [{ name: "web", count: 12 }],
  appVersions: [{ name: "0.1.0 (abc1234 2027-03-04)", count: 12 }],
  daily: [
    { date: "2027-03-03", count: 5 },
    { date: "2027-03-04", count: 7 },
  ],
};

const show = (read: () => Promise<Record<string, unknown> | null>) =>
  render(
    <MemoryRouter>
      <Usage read={read} />
    </MemoryRouter>,
  );

afterEach(cleanup);

describe("Usage", () => {
  beforeEach(() => setRoles(ready("developer")));

  it("renders the rollup", async () => {
    show(() => Promise.resolve(fixture));
    expect(await screen.findByText("Tabs opened")).toBeTruthy();
    expect(screen.getByText("device")).toBeTruthy();
    expect(screen.getByRole("row", { name: /Scout/ }).textContent).toContain(
      "8",
    );
    expect(screen.getByText("Platforms")).toBeTruthy();
    expect(
      screen.getByText("Busiest day: 7. A competition week should stand out."),
    ).toBeTruthy();
    expect(screen.getByText(/Rolled up 2027/)).toBeTruthy();
  });

  it("says so when the job has not run", async () => {
    show(() => Promise.resolve(null));
    expect(await screen.findByText(/No usage rollup yet/)).toBeTruthy();
  });

  it("says so when nothing was counted", async () => {
    show(() => Promise.resolve({ windowDays: 30 }));
    expect(await screen.findByText("Nothing recorded yet")).toBeTruthy();
  });

  it("names a refused read and retries", async () => {
    const read = vi
      .fn()
      .mockRejectedValueOnce({ code: "permission-denied" })
      .mockResolvedValueOnce(fixture);
    show(read);
    expect(
      await screen.findByText("Usage data is limited to the developer role."),
    ).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    expect(await screen.findByText("Tabs opened")).toBeTruthy();
  });

  it("is not available to other roles and reads nothing", async () => {
    for (const role of ["strategy", "admin", "scouter", "mentor"] as const) {
      setRoles(ready(role));
      const read = vi.fn(() => Promise.resolve(fixture));
      const view = show(read);
      expect(screen.getByText("Not available for your role")).toBeTruthy();
      expect(screen.queryByText("Tabs opened")).toBeNull();
      view.unmount();
    }
  });
});

describe("SharePanel", () => {
  beforeEach(() => {
    localStorage.clear();
    sharingStore.reload();
  });

  it("is on by default and turns off and on, kept on the device", async () => {
    render(<SharePanel />);
    const box = screen.getByRole("checkbox", {
      name: "Share anonymous usage data",
    });
    expect((box as HTMLInputElement).checked).toBe(true);
    fireEvent.click(box);
    await waitFor(() => expect((box as HTMLInputElement).checked).toBe(false));
    expect(localStorage.getItem("ss.telemetry.enabled")).toBe("0");
    expect(sharingStore.get()).toBe(false);
    fireEvent.click(box);
    expect(sharingStore.get()).toBe(true);
  });
});
