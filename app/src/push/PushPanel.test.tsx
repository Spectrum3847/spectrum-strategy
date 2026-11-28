// @vitest-environment jsdom
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { PushStatus } from "./client";
import { PushPanel } from "./PushPanel";

const mocks = vi.hoisted(() => ({
  status: { state: "off", id: null } as PushStatus,
  signedIn: true,
  training: false,
  online: true,
  outbox: [] as { path: string; status: string; error?: string }[],
  readStatus: vi.fn(),
  turnOn: vi.fn(),
  turnOff: vi.fn(),
  sendTest: vi.fn(),
  listeners: new Set<() => void>(),
}));

vi.mock("./client", () => ({
  readStatus: mocks.readStatus,
  turnOn: mocks.turnOn,
  turnOff: mocks.turnOff,
  sendTest: mocks.sendTest,
}));
vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({
    status: mocks.signedIn ? "signed-in" : "signed-out",
    uid: mocks.signedIn ? "u1" : null,
  }),
}));
vi.mock("../outbox/useOutbox", () => ({ useOutbox: () => mocks.outbox }));
vi.mock("../outbox/outbox", () => ({
  getOutbox: () => mocks.outbox,
  subscribeOutbox: (notify: () => void) => {
    mocks.listeners.add(notify);
    return () => mocks.listeners.delete(notify);
  },
}));
vi.mock("../training/session", () => ({
  useTrainingSession: () => (mocks.training ? {} : null),
}));
vi.mock("../ui/useOnline", () => ({ useOnline: () => mocks.online }));

function setStatus(status: PushStatus) {
  mocks.status = status;
  mocks.readStatus.mockImplementation(() => Promise.resolve(mocks.status));
}

beforeEach(() => {
  mocks.signedIn = true;
  mocks.training = false;
  mocks.online = true;
  mocks.outbox = [];
  mocks.listeners.clear();
  mocks.turnOn.mockReset();
  mocks.turnOff.mockReset();
  mocks.sendTest.mockReset();
  setStatus({ state: "off", id: null });
});
afterEach(cleanup);

const ready = (text: RegExp | string) => screen.findByText(text);

describe("PushPanel", () => {
  it("offers to turn reminders on and asks for permission only on the tap", async () => {
    render(<PushPanel />);
    const button = await screen.findByRole("button", {
      name: "Turn on reminders",
    });
    expect(mocks.turnOn).not.toHaveBeenCalled();

    mocks.turnOn.mockImplementation(() => {
      setStatus({ state: "on", id: "abc" });
      return Promise.resolve({ ok: true });
    });
    fireEvent.click(button);
    expect(await ready("Reminders are on for this device.")).toBeTruthy();
    expect(mocks.turnOn).toHaveBeenCalledWith("u1");
    expect(screen.getByRole("button", { name: "Send a test" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Turn off" })).toBeTruthy();
  });

  it("shows why it could not turn on", async () => {
    mocks.turnOn.mockResolvedValue({
      ok: false,
      message: "The browser could not subscribe: nope.",
    });
    render(<PushPanel />);
    fireEvent.click(
      await screen.findByRole("button", { name: "Turn on reminders" }),
    );
    expect((await screen.findByRole("alert")).textContent).toMatch(
      /could not subscribe/,
    );
  });

  it("sends a test and reports the answer", async () => {
    setStatus({ state: "on", id: "abc" });
    mocks.sendTest.mockResolvedValue({ ok: true, text: "Sent. Look for it." });
    render(<PushPanel />);
    fireEvent.click(await screen.findByRole("button", { name: "Send a test" }));
    expect((await screen.findByRole("status")).textContent).toBe(
      "Sent. Look for it.",
    );
  });

  it("waits for the subscription to reach the database before testing", async () => {
    setStatus({ state: "on", id: "abc" });
    mocks.outbox = [{ path: "pushSubscriptions/abc", status: "sending" }];
    mocks.sendTest.mockResolvedValue({ ok: true, text: "Sent. Look for it." });
    render(<PushPanel />);
    fireEvent.click(await screen.findByRole("button", { name: "Send a test" }));
    await new Promise((done) => setTimeout(done, 0));
    expect(mocks.sendTest).not.toHaveBeenCalled();
    mocks.outbox = [{ path: "pushSubscriptions/abc", status: "in-database" }];
    for (const notify of [...mocks.listeners]) notify();
    expect((await screen.findByRole("status")).textContent).toBe(
      "Sent. Look for it.",
    );
    expect(mocks.sendTest).toHaveBeenCalledTimes(1);
  });

  it("turns reminders off", async () => {
    setStatus({ state: "on", id: "abc" });
    mocks.turnOff.mockImplementation(() => {
      setStatus({ state: "off", id: null });
      return Promise.resolve();
    });
    render(<PushPanel />);
    fireEvent.click(await screen.findByRole("button", { name: "Turn off" }));
    expect(await ready("Reminders are off for this device.")).toBeTruthy();
    expect(
      await screen.findByRole("button", { name: "Turn on reminders" }),
    ).toBeTruthy();
  });

  it("shows whether the saved device is in the database", async () => {
    setStatus({ state: "on", id: "abc" });
    mocks.outbox = [
      { path: "pushSubscriptions/abc", status: "refused", error: "no" },
    ];
    render(<PushPanel />);
    expect(await ready("Refused: no")).toBeTruthy();
  });

  it("explains the Home Screen steps on an iPhone in a browser tab, with no buttons", async () => {
    setStatus({ state: "needs-home-screen", id: null });
    render(<PushPanel />);
    expect(await ready(/need the app on your Home Screen/)).toBeTruthy();
    expect(screen.getByText(/Add to Home Screen/)).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("says when notifications are blocked", async () => {
    setStatus({ state: "denied", id: null });
    render(<PushPanel />);
    expect(await ready(/blocked for this app/)).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("says when the browser cannot do push", async () => {
    setStatus({ state: "unsupported", id: null });
    render(<PushPanel />);
    expect(await ready(/cannot receive push notifications/)).toBeTruthy();
    expect(screen.queryByRole("button")).toBeNull();
  });

  it("disables turning on when signed out, offline or in training", async () => {
    mocks.signedIn = false;
    const view = render(<PushPanel />);
    const button = await screen.findByRole("button", {
      name: "Turn on reminders",
    });
    expect((button as HTMLButtonElement).disabled).toBe(true);
    expect(screen.getByText("Sign in to turn reminders on.")).toBeTruthy();
    view.unmount();

    mocks.signedIn = true;
    mocks.online = false;
    const offline = render(<PushPanel />);
    await waitFor(() =>
      expect(
        (
          screen.getByRole("button", {
            name: "Turn on reminders",
          }) as HTMLButtonElement
        ).disabled,
      ).toBe(true),
    );
    expect(screen.getByText(/Needs a connection/)).toBeTruthy();
    offline.unmount();

    mocks.online = true;
    mocks.training = true;
    render(<PushPanel />);
    await screen.findByText("Not available in training mode.");
    expect(
      (
        screen.getByRole("button", {
          name: "Turn on reminders",
        }) as HTMLButtonElement
      ).disabled,
    ).toBe(true);
  });
});
