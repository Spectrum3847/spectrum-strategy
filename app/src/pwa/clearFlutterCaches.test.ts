import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import { describe, expect, it, vi } from "vitest";

async function activate(names: string[], failKeys = false) {
  let activateListener: ((event: unknown) => void) | undefined;
  const deleted: string[] = [];
  const caches = {
    keys: () =>
      failKeys ? Promise.reject(new Error("denied")) : Promise.resolve(names),
    delete: vi.fn((name: string) => {
      deleted.push(name);
      return Promise.resolve(true);
    }),
  };
  const code = readFileSync(
    new URL("../../public/clear-flutter-caches-sw.js", import.meta.url),
    "utf8",
  );
  runInNewContext(code, {
    self: {
      addEventListener: (type: string, listener: (event: unknown) => void) => {
        if (type === "activate") activateListener = listener;
      },
    },
    caches,
  });
  let done: Promise<unknown> = Promise.resolve();
  activateListener?.({
    waitUntil: (p: Promise<unknown>) => {
      done = p;
    },
  });
  await done;
  return deleted;
}

describe("clear Flutter caches on activate", () => {
  it("deletes spectrum- caches and leaves workbox caches alone", async () => {
    const deleted = await activate([
      "spectrum-strategy-abc123",
      "spectrum-strategy-def456",
      "workbox-precache-v2-https://app.example.test/",
      "workbox-runtime-https://app.example.test/",
    ]);
    expect(deleted).toEqual([
      "spectrum-strategy-abc123",
      "spectrum-strategy-def456",
    ]);
  });

  it("matches the prefix only at the start of the name", async () => {
    const deleted = await activate(["my-spectrum-cache", "Spectrum-x"]);
    expect(deleted).toEqual([]);
  });

  it("does not fail activation when the cache list cannot be read", async () => {
    await expect(activate([], true)).resolves.toEqual([]);
  });
});
