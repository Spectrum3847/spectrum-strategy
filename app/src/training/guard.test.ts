// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from "vitest";

const firestore = vi.hoisted(() => ({ setDoc: vi.fn() }));

vi.mock("../firebase/client", () => ({ dataAuth: {}, db: {} }));
vi.mock("firebase/auth", () => ({ onAuthStateChanged: vi.fn() }));
vi.mock("firebase/firestore", async (importActual) => ({
  ...(await importActual<typeof import("firebase/firestore")>()),
  ...firestore,
}));

import { enqueueWrite } from "../outbox/outbox";
import { buildReplay } from "./replay";
import { leaveTraining, startTraining, TrainingWriteError } from "./session";

afterEach(() => leaveTraining());

describe("outbox guard", () => {
  it("refuses every write while training, so none reaches Firestore", async () => {
    startTraining("2026test", buildReplay([], []));
    await expect(
      enqueueWrite("matchBriefs/x", { id: "x" }, "Brief"),
    ).rejects.toBeInstanceOf(TrainingWriteError);
    expect(firestore.setDoc).not.toHaveBeenCalled();
  });
});
