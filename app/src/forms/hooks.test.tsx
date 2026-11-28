// @vitest-environment jsdom
import { act, cleanup, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useSettled } from "./hooks";

const mocks = vi.hoisted(() => ({ status: "signed-in" }));
vi.mock("../auth/AuthProvider", () => ({
  useAuth: () => ({ status: mocks.status }),
}));
vi.mock("../auth/rolesContext", () => ({ useRoles: () => ({}) }));

const feed = (ready: boolean) => ({ items: [], ready, failed: false });

beforeEach(() => {
  vi.useFakeTimers();
  mocks.status = "signed-in";
});
afterEach(() => {
  cleanup();
  vi.useRealTimers();
});

describe("useSettled", () => {
  it("is true once the first snapshot arrived", () => {
    const { result } = renderHook(() => useSettled(feed(true)));
    expect(result.current).toBe(true);
  });

  it("waits for the first snapshot, then gives up after a while", () => {
    const { result } = renderHook(() => useSettled(feed(false)));
    expect(result.current).toBe(false);
    act(() => {
      vi.advanceTimersByTime(4000);
    });
    expect(result.current).toBe(true);
  });

  it("does not wait when signed out", () => {
    mocks.status = "signed-out";
    const { result } = renderHook(() => useSettled(feed(false)));
    expect(result.current).toBe(true);
  });
});
