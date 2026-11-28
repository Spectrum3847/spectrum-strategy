import { describe, expect, it, vi } from "vitest";
import type { Outcome } from "../photos/state";
import { uploadScreenshots } from "./screenshots";

const file = (name: string) => new File(["x"], name, { type: "image/png" });
const stored = (key: string): Outcome => ({
  type: "response",
  status: 201,
  key,
});

const deps = (outcomes: Outcome[]) => {
  const upload = vi.fn(async (_blob: Blob) => outcomes.shift() ?? stored("x"));
  const prepare = vi.fn(async (f: File) => f as Blob);
  return { upload, prepare };
};

describe("uploadScreenshots", () => {
  it("keeps the key of each image that landed, in order", async () => {
    const d = deps([stored("a.jpg"), stored("b.jpg")]);
    expect(await uploadScreenshots([file("1"), file("2")], d)).toEqual({
      keys: ["a.jpg", "b.jpg"],
      dropped: 0,
    });
  });

  it("uploads at most three, one after the other", async () => {
    let running = 0;
    let most = 0;
    const d = {
      prepare: async (f: File) => f as Blob,
      upload: async () => {
        running += 1;
        most = Math.max(most, running);
        await Promise.resolve();
        running -= 1;
        return stored("k");
      },
    };
    const result = await uploadScreenshots(
      ["1", "2", "3", "4", "5"].map(file),
      d,
    );
    expect(result.keys).toHaveLength(3);
    expect(most).toBe(1);
  });

  it("drops an image that could not upload and keeps the rest", async () => {
    const d = deps([
      { type: "unavailable", reason: "offline" },
      stored("b.jpg"),
      { type: "response", status: 413 },
      { type: "network" },
    ]);
    const result = await uploadScreenshots(
      [file("1"), file("2"), file("3")],
      d,
    );
    expect(result).toEqual({ keys: ["b.jpg"], dropped: 2 });
  });

  it("drops an image that cannot be read, without calling the Worker", async () => {
    const upload = vi.fn(async () => stored("k"));
    const result = await uploadScreenshots([file("1")], {
      prepare: async () => {
        throw new Error("not an image");
      },
      upload,
    });
    expect(result).toEqual({ keys: [], dropped: 1 });
    expect(upload).not.toHaveBeenCalled();
  });

  it("drops a created response that has no key", async () => {
    const d = deps([{ type: "response", status: 201 }]);
    expect(await uploadScreenshots([file("1")], d)).toEqual({
      keys: [],
      dropped: 1,
    });
  });

  it("does nothing for no images", async () => {
    const d = deps([]);
    expect(await uploadScreenshots([], d)).toEqual({ keys: [], dropped: 0 });
    expect(d.upload).not.toHaveBeenCalled();
  });
});
