// @vitest-environment jsdom
import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SavedEntry } from "./local";
import {
  qrConfig,
  referencePayload,
  referenceScanId,
  schedule,
} from "./qr.fixture";
import { ScanCamera } from "./ScanCamera";
import { ScanStation, type ScanStationProps } from "./ScanStation";

vi.mock("./decoder", () => ({
  decodeFrame: vi.fn(() => Promise.resolve(null)),
}));

let sendCode: (text: string) => void = () => undefined;
function FakeCamera({ onCode }: { onCode(text: string): void }) {
  sendCode = onCode;
  return <div data-testid="camera" />;
}

let persisted: { doc: Record<string, unknown>; entry: SavedEntry }[] = [];

function props(over: Partial<ScanStationProps> = {}): ScanStationProps {
  return {
    config: qrConfig,
    schedule,
    eventKey: "2027test",
    author: { uid: "uid-1", displayName: "Sam Scout" },
    remote: [],
    saved: [],
    deliveryOf: () => ({ status: "sending" }),
    persist: async (doc, entry) => {
      persisted.push({ doc, entry });
    },
    Camera: FakeCamera,
    repeatMs: 3000,
    ...over,
  };
}

const view = (p: ScanStationProps) =>
  render(
    <MemoryRouter>
      <ScanStation {...p} />
    </MemoryRouter>,
  );

beforeEach(() => {
  persisted = [];
  vi.useRealTimers();
});
afterEach(cleanup);

describe("scan station", () => {
  it("saves a scan through the outbox under the reference scan id", async () => {
    view(props());
    act(() => sendCode(referencePayload));
    expect(await screen.findByText("Team 1234, match 12 at R2")).toBeTruthy();
    expect(persisted).toHaveLength(1);
    expect(persisted[0]?.entry.id).toBe(referenceScanId);
    expect(persisted[0]?.doc.id).toBe(referenceScanId);
    expect(screen.getByText("1 added")).toBeTruthy();
    expect(screen.getByText("Sending")).toBeTruthy();
  });

  it("keeps scanning and lists each entry newest first", async () => {
    view(props());
    act(() => sendCode(referencePayload));
    await screen.findByText("1 added");
    act(() => sendCode(referencePayload.replace("\t7\t", "\t8\t")));
    await screen.findByText("2 added");
    expect(persisted).toHaveLength(2);
    expect(screen.getByTestId("camera")).toBeTruthy();
  });

  it("ignores a code held in view and a copy it already holds", async () => {
    view(props());
    act(() => sendCode(referencePayload));
    await screen.findByText("1 added");
    act(() => sendCode(referencePayload));
    expect(persisted).toHaveLength(1);
    expect(screen.getByText("0 already had")).toBeTruthy();
  });

  it("does not add a copy that the database or this device already has", async () => {
    view(
      props({
        remote: [{ id: referenceScanId, tbaMatchKey: null, fieldValues: {} }],
      }),
    );
    act(() => sendCode(referencePayload));
    expect(await screen.findByText("1 already had")).toBeTruthy();
    expect(screen.getByText("Already had this entry")).toBeTruthy();
    expect(persisted).toHaveLength(0);
  });

  it("reports a code that is not scout data and keeps going", async () => {
    view(props());
    act(() => sendCode("https://example.com"));
    expect(
      await screen.findByText("This is not scout data for the current form."),
    ).toBeTruthy();
    expect(screen.getByText("1 not read")).toBeTruthy();
    act(() => sendCode(referencePayload));
    await screen.findByText("1 added");
  });

  it("says when saving failed and lets the same code be scanned again", async () => {
    let fail = true;
    view(
      props({
        persist: async (doc, entry) => {
          if (fail) throw new Error("storage");
          persisted.push({ doc, entry });
        },
      }),
    );
    act(() => sendCode(referencePayload));
    expect(await screen.findByText(/Nothing was recorded/)).toBeTruthy();
    fail = false;
    act(() => sendCode(referencePayload));
    expect(await screen.findByText("1 added")).toBeTruthy();
    expect(persisted).toHaveLength(1);
  });

  it("needs a signed-in user and shows no camera without one", () => {
    view(props({ author: { uid: null, displayName: null } }));
    expect(screen.getByRole("alert").textContent).toContain("Sign in");
    expect(screen.queryByTestId("camera")).toBeNull();
  });

  it("has a Done link back to the Scout tab", () => {
    view(props());
    expect(
      screen.getByRole("link", { name: "Done" }).getAttribute("href"),
    ).toBe("/scout");
  });
});

describe("camera", () => {
  const getUserMedia = vi.fn();
  const stop = vi.fn();

  beforeEach(() => {
    getUserMedia.mockReset();
    stop.mockReset();
    Object.defineProperty(navigator, "mediaDevices", {
      configurable: true,
      value: { getUserMedia },
    });
    HTMLMediaElement.prototype.play = vi.fn(() => Promise.resolve());
  });

  const denied = () =>
    Promise.reject(new DOMException("blocked", "NotAllowedError"));

  it("asks for the camera only when it mounts and explains a denial", async () => {
    getUserMedia.mockImplementation(denied);
    expect(getUserMedia).not.toHaveBeenCalled();
    render(<ScanCamera onCode={() => undefined} />);
    expect(await screen.findByText(/Camera access is blocked/)).toBeTruthy();
    expect(getUserMedia).toHaveBeenCalledTimes(1);
    expect(getUserMedia.mock.calls[0]?.[0]).toMatchObject({
      video: { facingMode: { ideal: "environment" } },
      audio: false,
    });
  });

  it("tries again on request", async () => {
    getUserMedia.mockImplementation(denied);
    render(<ScanCamera onCode={() => undefined} />);
    fireEvent.click(await screen.findByRole("button", { name: "Try again" }));
    await waitFor(() => expect(getUserMedia).toHaveBeenCalledTimes(2));
  });

  it("says when there is no camera", async () => {
    getUserMedia.mockImplementation(() =>
      Promise.reject(new DOMException("none", "NotFoundError")),
    );
    render(<ScanCamera onCode={() => undefined} />);
    expect(await screen.findByText(/No camera is available/)).toBeTruthy();
  });

  it("says when the page has no camera API at all", async () => {
    Object.defineProperty(navigator, "mediaDevices", {
      configurable: true,
      value: undefined,
    });
    render(<ScanCamera onCode={() => undefined} />);
    expect(await screen.findByText(/No camera is available/)).toBeTruthy();
  });

  it("scans, then stops every track when it unmounts", async () => {
    getUserMedia.mockResolvedValue({
      getTracks: () => [{ stop }, { stop }],
    });
    const { unmount } = render(<ScanCamera onCode={() => undefined} />);
    await waitFor(() =>
      expect(document.querySelector('[data-state="scanning"]')).toBeTruthy(),
    );
    expect(screen.queryByRole("button", { name: "Try again" })).toBeNull();
    unmount();
    expect(stop).toHaveBeenCalledTimes(2);
  });

  it("releases a camera that arrives after it was already closed", async () => {
    let resolve: (s: unknown) => void = () => undefined;
    getUserMedia.mockImplementation(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    );
    const { unmount } = render(<ScanCamera onCode={() => undefined} />);
    unmount();
    resolve({ getTracks: () => [{ stop }] });
    await waitFor(() => expect(stop).toHaveBeenCalledTimes(1));
  });
});
