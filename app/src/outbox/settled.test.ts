import { describe, expect, it } from "vitest";
import type { OutboxStatus } from "./confirm";
import { whenInDatabase } from "./settled";

function fakeOutbox(items: { path: string; status: OutboxStatus }[]) {
  const listeners = new Set<() => void>();
  return {
    items,
    read: () => items,
    subscribe: (notify: () => void) => {
      listeners.add(notify);
      return () => listeners.delete(notify);
    },
    set(next: { path: string; status: OutboxStatus }[]) {
      items.splice(0, items.length, ...next);
      for (const l of [...listeners]) l();
    },
    listening: () => listeners.size,
  };
}

describe("whenInDatabase", () => {
  it("waits for the newest item for the path to reach the database", async () => {
    const box = fakeOutbox([{ path: "p/1", status: "sending" }]);
    const done = whenInDatabase("p/1", box.read, box.subscribe);
    box.set([{ path: "p/1", status: "in-database" }]);
    await expect(done).resolves.toBe(true);
    expect(box.listening()).toBe(0);
  });

  it("is false when the write is refused or dismissed", async () => {
    const refused = fakeOutbox([{ path: "p/1", status: "on-device" }]);
    const a = whenInDatabase("p/1", refused.read, refused.subscribe);
    refused.set([{ path: "p/1", status: "refused" }]);
    await expect(a).resolves.toBe(false);
    const gone = fakeOutbox([{ path: "p/1", status: "sending" }]);
    const b = whenInDatabase("p/1", gone.read, gone.subscribe);
    gone.set([]);
    await expect(b).resolves.toBe(false);
  });
});
