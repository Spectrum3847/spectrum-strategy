import { beforeEach, describe, expect, it, vi } from "vitest";
import { createQueue, type QueueDeps } from "./queue";
import { newItem, type Outcome, retryGapMs, waitingEntry } from "./state";
import { memoryStore, type PhotoStore } from "./store";

const blob = new Blob(["x"], { type: "image/jpeg" });
const uploaded = (key: string): Outcome => ({
  type: "response",
  status: 201,
  key,
});
const day = 24 * 60 * 60 * 1000;

let clock = Date.parse("2027-03-05T18:00:00.000Z");

function setup(
  over: Partial<QueueDeps> = {},
  store: PhotoStore = memoryStore(),
) {
  const upload = vi.fn<(b: Blob) => Promise<Outcome>>(async () =>
    uploaded("k1.jpg"),
  );
  const deleteRemote = vi.fn<(key: string) => Promise<boolean>>(
    async () => true,
  );
  const attach = vi.fn<(id: string, keys: string[]) => Promise<string[]>>(
    async () => [],
  );
  const queue = createQueue({
    store,
    upload,
    deleteRemote,
    attach,
    now: () => clock,
    ...over,
  });
  return { queue, upload, deleteRemote, attach };
}

beforeEach(() => {
  clock = Date.parse("2027-03-05T18:00:00.000Z");
});

describe("waiting photos", () => {
  it("uploads a photo with no entry yet but does not attach it", async () => {
    const { queue, upload, attach } = setup();
    await queue.add(waitingEntry, 1111, blob, "2027test");
    await queue.pass();
    expect(upload).toHaveBeenCalledTimes(1);
    expect(attach).not.toHaveBeenCalled();
    expect(queue.items()[0]).toMatchObject({
      state: "uploaded",
      entryId: waitingEntry,
      eventKey: "2027test",
    });
  });

  it("attaches it to the entry it is placed on", async () => {
    const attach = vi.fn<(id: string, keys: string[]) => Promise<string[]>>(
      async (_id, keys) => keys,
    );
    const { queue } = setup({ attach });
    const added = await queue.add(waitingEntry, 1111, blob, "2027test");
    await queue.pass();
    queue.place(new Map([[added.id, "e7"]]));
    await queue.pass();
    expect(attach).toHaveBeenCalledWith("e7", ["k1.jpg"]);
    expect(queue.items()[0]).toMatchObject({
      entryId: "e7",
      state: "attached",
    });
  });

  it("does not move a photo that is no longer waiting", async () => {
    const { queue } = setup();
    const added = await queue.add("e1", 1111, blob);
    queue.place(new Map([[added.id, "e7"]]));
    expect(queue.items()[0]?.entryId).toBe("e1");
  });
});

describe("photo queue", () => {
  it("uploads a photo and leaves it uploaded while the entry is unsaved", async () => {
    const { queue, upload, attach } = setup();
    const added = await queue.add("e1", 1111, blob);
    await queue.pass();
    expect(upload).toHaveBeenCalledTimes(1);
    expect(queue.items().find((i) => i.id === added.id)).toMatchObject({
      state: "uploaded",
      key: "k1.jpg",
    });
    expect(attach).toHaveBeenCalledWith("e1", ["k1.jpg"]);
  });

  it("marks a photo attached once the saved entry holds its key", async () => {
    const { queue, deleteRemote } = setup({
      attach: async (_id, keys) => keys,
    });
    await queue.add("e1", 1111, blob);
    await queue.pass();
    expect(queue.items()[0]?.state).toBe("attached");
    expect(deleteRemote).not.toHaveBeenCalled();
  });

  it("keeps a photo waiting while offline, then uploads on the next pass", async () => {
    const upload = vi
      .fn<(b: Blob) => Promise<Outcome>>()
      .mockResolvedValueOnce({ type: "unavailable", reason: "offline" })
      .mockResolvedValue(uploaded("k2.jpg"));
    const { queue } = setup({ upload });
    await queue.add("e1", 1111, blob);
    await vi.waitFor(() =>
      expect(queue.items()[0]).toMatchObject({
        state: "waiting",
        error: "Waiting for a connection",
        attempts: 0,
      }),
    );
    await queue.pass();
    expect(queue.items()[0]).toMatchObject({
      state: "uploaded",
      key: "k2.jpg",
    });
  });

  it("retries a network failure only after the gap, and stops after five", async () => {
    const upload = vi
      .fn<(b: Blob) => Promise<Outcome>>()
      .mockResolvedValue({ type: "network" });
    const { queue } = setup({ upload });
    await queue.add("e1", 1111, blob);
    await queue.pass();
    expect(upload).toHaveBeenCalledTimes(1);
    await queue.pass();
    expect(upload).toHaveBeenCalledTimes(1);
    for (let i = 0; i < 6; i++) {
      clock += retryGapMs;
      await queue.pass();
    }
    expect(upload).toHaveBeenCalledTimes(5);
    expect(queue.items()[0]?.state).toBe("failed");
  });

  it("uploads again when the scout retries a failed photo", async () => {
    const upload = vi
      .fn<(b: Blob) => Promise<Outcome>>()
      .mockResolvedValueOnce({ type: "response", status: 413 })
      .mockResolvedValue(uploaded("k3.jpg"));
    const { queue } = setup({ upload });
    const added = await queue.add("e1", 1111, blob);
    await queue.pass();
    expect(queue.items()[0]?.state).toBe("failed");
    queue.retry(added.id);
    await queue.pass();
    expect(queue.items()[0]).toMatchObject({
      state: "uploaded",
      key: "k3.jpg",
    });
  });

  it("deletes an uploaded photo from the bucket when it is discarded", async () => {
    const { queue, deleteRemote } = setup();
    const added = await queue.add("e1", 1111, blob);
    await queue.pass();
    await queue.discard(added.id);
    expect(queue.items()).toEqual([]);
    expect(deleteRemote).toHaveBeenCalledWith("k1.jpg");
  });

  it("deletes the object of a photo discarded during its upload", async () => {
    let finish: (o: Outcome) => void = () => undefined;
    const upload = vi.fn(
      () => new Promise<Outcome>((resolve) => (finish = resolve)),
    );
    const { queue, deleteRemote } = setup({ upload });
    const added = await queue.add("e1", 1111, blob);
    await vi.waitFor(() => expect(upload).toHaveBeenCalled());
    expect(queue.items()[0]?.state).toBe("uploading");
    const gone = queue.discard(added.id);
    finish(uploaded("late.jpg"));
    await gone;
    expect(queue.items()).toEqual([]);
    expect(deleteRemote).toHaveBeenCalledWith("late.jpg");
  });

  it("releases a removed key from the bucket and the device", async () => {
    const { queue, deleteRemote } = setup({
      attach: async (_id, keys) => keys,
    });
    await queue.add("e1", 1111, blob);
    await queue.pass();
    await queue.release(["k1.jpg", "other.jpg"]);
    expect(queue.items()).toEqual([]);
    expect(deleteRemote).toHaveBeenCalledWith("k1.jpg");
    expect(deleteRemote).toHaveBeenCalledWith("other.jpg");
  });

  it("restores saved photos after a reload and restarts an interrupted upload", async () => {
    const store = memoryStore();
    const interrupted = newItem("p1", "e1", 1111, blob, new Date(clock));
    await store.put({ ...interrupted, state: "uploading" });
    const upload = vi.fn(async () => ({ type: "network" }) as Outcome);
    const { queue } = setup({ upload }, store);
    await queue.start();
    expect(queue.items()[0]?.state).toBe("waiting");
    await queue.pass();
    expect(upload).toHaveBeenCalledTimes(1);
  });

  it("sweeps a photo that never reached an entry, and its object", async () => {
    const { queue, deleteRemote } = setup();
    await queue.add("e1", 1111, blob);
    await queue.pass();
    clock += 15 * day;
    await queue.pass();
    expect(queue.items()).toEqual([]);
    expect(deleteRemote).toHaveBeenCalledWith("k1.jpg");
  });

  it("keeps working when the device store refuses a write", async () => {
    const broken: PhotoStore = {
      load: async () => [],
      put: async () => {
        throw new Error("quota");
      },
      remove: async () => undefined,
    };
    const spy = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const { queue } = setup({}, broken);
    await queue.add("e1", 1111, blob);
    await queue.pass();
    expect(queue.items()[0]?.state).toBe("uploaded");
    spy.mockRestore();
  });

  it("notifies subscribers as photos change", async () => {
    const { queue } = setup();
    const seen = vi.fn();
    queue.subscribe(seen);
    await queue.add("e1", 1111, blob);
    expect(seen).toHaveBeenCalled();
  });
});
