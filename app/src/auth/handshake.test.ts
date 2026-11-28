import { describe, expect, it, vi } from "vitest";
import {
  classifyHandshakeError,
  type HandshakeDeps,
  HandshakeError,
  signInThroughCentral,
} from "./handshake";

function makeDeps(overrides: Partial<HandshakeDeps> = {}): HandshakeDeps {
  return {
    appKey: "example-app",
    signInWithGoogle: vi.fn().mockResolvedValue(undefined),
    getCustomToken: vi.fn().mockResolvedValue({ customToken: "token-1" }),
    signInWithCustomToken: vi.fn().mockResolvedValue(undefined),
    signOutCentral: vi.fn().mockResolvedValue(undefined),
    ...overrides,
  };
}

describe("signInThroughCentral", () => {
  it("runs Google, the callable, then the custom token in order", async () => {
    const calls: string[] = [];
    const deps = makeDeps({
      signInWithGoogle: vi.fn(async () => {
        calls.push("google");
      }),
      getCustomToken: vi.fn(async (app: string) => {
        calls.push(`token:${app}`);
        return { customToken: "token-1" };
      }),
      signInWithCustomToken: vi.fn(async (token: string) => {
        calls.push(`custom:${token}`);
      }),
    });
    await signInThroughCentral(deps);
    expect(calls).toEqual(["google", "token:example-app", "custom:token-1"]);
    expect(deps.signOutCentral).not.toHaveBeenCalled();
  });

  it("shows not-approved and never signs in to the data project", async () => {
    const deps = makeDeps({
      getCustomToken: vi
        .fn()
        .mockRejectedValue({ code: "functions/permission-denied" }),
    });
    await expect(signInThroughCentral(deps)).rejects.toMatchObject({
      kind: "not-approved",
    });
    expect(deps.signInWithCustomToken).not.toHaveBeenCalled();
    expect(deps.signOutCentral).toHaveBeenCalled();
  });

  it("maps not-found to app-not-registered", async () => {
    const deps = makeDeps({
      getCustomToken: vi
        .fn()
        .mockRejectedValue({ code: "functions/not-found" }),
    });
    await expect(signInThroughCentral(deps)).rejects.toMatchObject({
      kind: "app-not-registered",
    });
  });

  it("refuses to start without an app key", async () => {
    const deps = makeDeps({ appKey: "" });
    await expect(signInThroughCentral(deps)).rejects.toMatchObject({
      kind: "no-app-key",
    });
    expect(deps.signInWithGoogle).not.toHaveBeenCalled();
  });

  it("treats a closed popup as a cancel", async () => {
    const deps = makeDeps({
      signInWithGoogle: vi
        .fn()
        .mockRejectedValue({ code: "auth/popup-closed-by-user" }),
    });
    await expect(signInThroughCentral(deps)).rejects.toMatchObject({
      kind: "popup-closed",
    });
    expect(deps.getCustomToken).not.toHaveBeenCalled();
  });
});

describe("classifyHandshakeError", () => {
  it("names a timeout or no connection to the sign-in service", () => {
    for (const code of [
      "functions/deadline-exceeded",
      "functions/unavailable",
      "auth/network-request-failed",
    ]) {
      const error = classifyHandshakeError(
        Object.assign(new Error(code), { code }),
      );
      expect(error.kind).toBe("unreachable");
    }
  });

  it("names a rejected or expired custom token", () => {
    for (const code of [
      "auth/invalid-custom-token",
      "auth/custom-token-mismatch",
      "auth/expired-custom-token",
    ]) {
      const error = classifyHandshakeError(
        Object.assign(new Error(code), { code }),
      );
      expect(error.kind).toBe("bad-token");
    }
  });

  it("wraps unknown errors", () => {
    const error = classifyHandshakeError(new Error("boom"));
    expect(error).toBeInstanceOf(HandshakeError);
    expect(error.kind).toBe("unknown");
    expect(error.message).toContain("boom");
  });
});
