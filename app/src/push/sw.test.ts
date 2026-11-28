import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { describe, expect, it, vi } from "vitest";

type Listener = (event: unknown) => void;

function load(
  windows: {
    url: string;
    focus: () => Promise<void>;
    navigate: (url: string) => Promise<void>;
  }[] = [],
) {
  const listeners = new Map<string, Listener>();
  const showNotification = vi.fn(() => Promise.resolve());
  const openWindow = vi.fn(() => Promise.resolve());
  const scope = {
    addEventListener: (type: string, listener: Listener) =>
      listeners.set(type, listener),
    registration: { showNotification },
    location: { origin: "https://app.example.test" },
    clients: { matchAll: () => Promise.resolve(windows), openWindow },
  };
  const code = readFileSync(
    new URL("../../public/push-sw.js", import.meta.url),
    "utf8",
  );
  runInNewContext(code, { self: scope, URL });
  return { listeners, showNotification, openWindow };
}

async function push(sw: ReturnType<typeof load>, data: unknown) {
  let done: Promise<unknown> = Promise.resolve();
  sw.listeners.get("push")?.({
    data: {
      json: () => {
        if (data instanceof Error) throw data;
        return data;
      },
    },
    waitUntil: (p: Promise<unknown>) => {
      done = p;
    },
  });
  await done;
}

async function click(sw: ReturnType<typeof load>, url: unknown) {
  let done: Promise<unknown> = Promise.resolve();
  const close = vi.fn();
  sw.listeners.get("notificationclick")?.({
    notification: { close, data: { url } },
    waitUntil: (p: Promise<unknown>) => {
      done = p;
    },
  });
  await done;
  return close;
}

describe("push", () => {
  it("shows the title and body, with a tag that renotifies", async () => {
    const sw = load();
    await push(sw, {
      title: "Your scouting shift starts in 3 matches",
      body: "Scout matches 7-12 at B2.",
      tag: "shift-e-7",
      url: "/scout",
    });
    expect(sw.showNotification).toHaveBeenCalledWith(
      "Your scouting shift starts in 3 matches",
      {
        body: "Scout matches 7-12 at B2.",
        icon: "/icons/Icon-192.png",
        tag: "shift-e-7",
        renotify: true,
        data: { url: "/scout" },
      },
    );
  });

  it("does not set renotify without a tag, which would throw", async () => {
    const sw = load();
    await push(sw, { title: "No tag" });
    const [, options] = sw.showNotification.mock.calls[0] as unknown as [
      string,
      { renotify: boolean; tag?: string },
    ];
    expect(options.tag).toBeUndefined();
    expect(options.renotify).toBe(false);
  });

  it("still shows a notification when the payload is empty or not JSON", async () => {
    const sw = load();
    await push(sw, new Error("not json"));
    expect(sw.showNotification).toHaveBeenCalledWith(
      "Spectrum Strategy",
      expect.objectContaining({ body: "", data: { url: "/" } }),
    );
  });

  it("falls back to the start page for a link that leaves the app", async () => {
    const sw = load();
    await push(sw, { title: "x", url: "https://evil.example/" });
    await push(sw, { title: "y", url: "//evil.example/" });
    for (const call of sw.showNotification.mock.calls) {
      expect(
        (call as unknown as [string, { data: { url: string } }])[1].data.url,
      ).toBe("/");
    }
  });
});

describe("notificationclick", () => {
  it("closes the notification and opens the app when no window is open", async () => {
    const sw = load();
    const close = await click(sw, "/scout");
    expect(close).toHaveBeenCalled();
    expect(sw.openWindow).toHaveBeenCalledWith(
      "https://app.example.test/scout",
    );
  });

  it("focuses an open window and moves it to the Scout tab", async () => {
    const focus = vi.fn(() => Promise.resolve());
    const navigate = vi.fn(() => Promise.resolve());
    const sw = load([
      { url: "https://app.example.test/settings", focus, navigate },
    ]);
    await click(sw, "/scout");
    expect(focus).toHaveBeenCalled();
    expect(navigate).toHaveBeenCalledWith("https://app.example.test/scout");
    expect(sw.openWindow).not.toHaveBeenCalled();
  });

  it("leaves a window that is already on the Scout tab alone", async () => {
    const navigate = vi.fn(() => Promise.resolve());
    const sw = load([
      {
        url: "https://app.example.test/scout",
        focus: () => Promise.resolve(),
        navigate,
      },
    ]);
    await click(sw, "/scout");
    expect(navigate).not.toHaveBeenCalled();
  });

  it("opens a new window when the open one cannot be navigated", async () => {
    const sw = load([
      {
        url: "https://app.example.test/",
        focus: () => Promise.resolve(),
        navigate: () => Promise.reject(new Error("not controlled")),
      },
    ]);
    await click(sw, "/scout");
    expect(sw.openWindow).toHaveBeenCalledWith(
      "https://app.example.test/scout",
    );
  });
});
