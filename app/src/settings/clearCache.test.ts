import { describe, expect, it } from "vitest";
import { type CacheEnv, clearAppCache } from "./clearCache";

describe("clearAppCache", () => {
  it("unregisters every worker and deletes every cache", async () => {
    const unregistered: string[] = [];
    const deleted: string[] = [];
    const reg = (id: string) => ({
      unregister: async () => {
        unregistered.push(id);
        return true;
      },
    });
    const env: CacheEnv = {
      registrations: async () => [reg("a"), reg("b")],
      cacheNames: async () => ["workbox-precache", "runtime"],
      deleteCache: async (name) => {
        deleted.push(name);
        return true;
      },
    };
    await clearAppCache(env);
    expect(unregistered).toEqual(["a", "b"]);
    expect(deleted).toEqual(["workbox-precache", "runtime"]);
  });

  it("does nothing when the browser has neither", async () => {
    await clearAppCache({
      registrations: async () => [],
      cacheNames: async () => [],
      deleteCache: async () => {
        throw new Error("nothing to delete");
      },
    });
  });
});
