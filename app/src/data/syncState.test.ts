import { beforeEach, describe, expect, it, vi } from "vitest";

const firestore = vi.hoisted(() => ({
  onSnapshot: vi.fn(),
}));
vi.mock("firebase/firestore", () => firestore);

import {
  noteClosed,
  noteFailed,
  noteSnapshot,
  syncNotes,
  watchTracked,
} from "./syncState";

beforeEach(() => {
  noteClosed("entries");
  noteSnapshot("entries", true, 0);
});

describe("sync notes", () => {
  it("stamps a server snapshot and keeps it when the cache takes over", () => {
    noteSnapshot("entries", false, 1000);
    expect(syncNotes().entries).toMatchObject({
      open: true,
      fromCache: false,
      lastServerMs: 1000,
    });
    noteSnapshot("entries", true, 5000);
    expect(syncNotes().entries).toMatchObject({
      fromCache: true,
      lastServerMs: 5000,
    });
    noteSnapshot("entries", true, 9000);
    expect(syncNotes().entries?.lastServerMs).toBe(5000);
  });

  it("does not claim a server answer for a cache-only start", () => {
    noteClosed("pit");
    noteSnapshot("pit", true, 100);
    expect(syncNotes().pit?.lastServerMs).toBeNull();
  });

  it("records a failure and a close", () => {
    noteFailed("entries");
    expect(syncNotes().entries?.failed).toBe(true);
    noteSnapshot("entries", false, 2000);
    expect(syncNotes().entries?.failed).toBe(false);
    noteClosed("entries");
    expect(syncNotes().entries?.open).toBe(false);
  });
});

describe("watchTracked", () => {
  it("passes only changes on, and notes every snapshot", () => {
    let emit: (snap: unknown) => void = () => undefined;
    const stop = vi.fn();
    firestore.onSnapshot.mockImplementation((_q, _o, next) => {
      emit = next;
      return stop;
    });
    const onSnap = vi.fn();
    const off = watchTracked("pit", {} as never, onSnap, () => undefined);
    const snap = (fromCache: boolean, changes: number) => ({
      metadata: { fromCache },
      docChanges: () => Array(changes).fill({}),
    });
    emit(snap(true, 0));
    emit(snap(false, 0));
    emit(snap(false, 2));
    expect(onSnap).toHaveBeenCalledTimes(2);
    expect(syncNotes().pit).toMatchObject({ fromCache: false });
    off();
    expect(stop).toHaveBeenCalled();
    expect(syncNotes().pit?.open).toBe(false);
  });
});
