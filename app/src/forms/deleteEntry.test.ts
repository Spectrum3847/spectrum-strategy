// @vitest-environment jsdom
import { beforeEach, describe, expect, it, vi } from "vitest";
import { net, photoQueue, resetQueue } from "../photos/fakeService";
import { deleteFormEntry, removePhotosOnceDeleted } from "./deleteEntry";

const outbox = vi.hoisted(() => ({
  status: "in-database",
  enqueueDelete: vi.fn((..._args: unknown[]) => Promise.resolve("o1")),
  getOutbox: () => [{ path: "pitScoutEntries/e1", status: outbox.status }],
  subscribeOutbox: () => () => undefined,
}));

vi.mock("../auth/AuthProvider", () => ({ useAuth: () => ({ uid: "u1" }) }));
vi.mock("../auth/rolesContext", () => ({ useRoles: () => ({}) }));
vi.mock("../outbox/outbox", () => outbox);
vi.mock("../photos/service", () => import("../photos/fakeService"));

beforeEach(async () => {
  outbox.enqueueDelete.mockClear();
  outbox.status = "in-database";
  await resetQueue();
});

describe("deleteFormEntry", () => {
  it("deletes a prescout entry and touches no photos", async () => {
    await deleteFormEntry("prescout", "p1", "Prescout deleted", ["a.jpg"]);
    expect(outbox.enqueueDelete).toHaveBeenCalledWith(
      "prescoutEntries/p1",
      "Prescout deleted",
    );
    expect(net.remove).not.toHaveBeenCalled();
  });

  it("deletes a pit entry, then its uploaded photos once confirmed", async () => {
    await deleteFormEntry("pit", "e1", "Pit deleted", ["a.jpg", "b.jpg"]);
    expect(outbox.enqueueDelete).toHaveBeenCalledWith(
      "pitScoutEntries/e1",
      "Pit deleted",
    );
    await vi.waitFor(() => expect(net.remove).toHaveBeenCalledWith("b.jpg"));
    expect(net.remove).toHaveBeenCalledWith("a.jpg");
  });

  it("drops photos still waiting on this device for the entry", async () => {
    net.upload.mockResolvedValue({ type: "network" });
    await photoQueue.add("e1", 1111, new Blob(["x"]));
    await photoQueue.add("e2", 2222, new Blob(["y"]));
    expect(await removePhotosOnceDeleted("pitScoutEntries/e1", "e1", [])).toBe(
      true,
    );
    expect(photoQueue.items().map((i) => i.entryId)).toEqual(["e2"]);
  });

  it("keeps the photos when the delete is refused", async () => {
    outbox.status = "refused";
    net.upload.mockResolvedValue({ type: "network" });
    await photoQueue.add("e1", 1111, new Blob(["x"]));
    expect(
      await removePhotosOnceDeleted("pitScoutEntries/e1", "e1", ["a.jpg"]),
    ).toBe(false);
    expect(net.remove).not.toHaveBeenCalled();
    expect(photoQueue.items().map((i) => i.entryId)).toEqual(["e1"]);
  });
});
