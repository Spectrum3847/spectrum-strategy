import { describe, expect, it } from "vitest";
import { type DeliveryInput, decideRemote, deliveryState } from "./sync";

describe("decideRemote", () => {
  const base = { mine: 100, theirs: 200, unsent: false, drawing: false };

  it("ignores this device's own write coming back and older versions", () => {
    expect(decideRemote({ ...base, theirs: 100 })).toBe("ignore");
    expect(decideRemote({ ...base, theirs: 50 })).toBe("ignore");
  });

  it("replaces a clean board with a newer version", () => {
    expect(decideRemote(base)).toBe("adopt");
  });

  it("waits for the stroke in progress", () => {
    expect(decideRemote({ ...base, drawing: true })).toBe("defer");
  });

  it("asks when this device has changes the database does not", () => {
    expect(decideRemote({ ...base, unsent: true })).toBe("conflict");
    expect(decideRemote({ ...base, unsent: true, drawing: true })).toBe(
      "conflict",
    );
  });
});

describe("deliveryState", () => {
  const input = (over: Partial<DeliveryInput> = {}): DeliveryInput => ({
    hasBoard: true,
    local: "saved",
    handed: true,
    signedIn: true,
    item: undefined,
    remote: "none",
    ...over,
  });

  it("says so when the device could not keep the drawing", () => {
    expect(deliveryState(input({ local: "failed" })).kind).toBe("failed");
  });

  it("says nothing is drawn on a blank board", () => {
    expect(deliveryState(input({ hasBoard: false })).kind).toBe("none");
  });

  it("claims only the device before the outbox has the change", () => {
    const state = deliveryState(
      input({ handed: false, item: { status: "in-database" } }),
    );
    expect(state).toEqual({ kind: "device", text: "Saved on this device" });
  });

  it("follows the outbox once the change is handed over", () => {
    const at = (status: "on-device" | "sending" | "in-database" | "refused") =>
      deliveryState(input({ item: { status } })).kind;
    expect(at("on-device")).toBe("device");
    expect(at("sending")).toBe("sending");
    expect(at("in-database")).toBe("database");
    expect(at("refused")).toBe("refused");
  });

  it("shows the reason a write was refused", () => {
    const state = deliveryState(
      input({ item: { status: "refused", error: "Missing permissions" } }),
    );
    expect(state.text).toBe("Refused by the database: Missing permissions");
  });

  it("does not call an unsent board sent while signed out", () => {
    expect(
      deliveryState(input({ signedIn: false, item: { status: "sending" } }))
        .kind,
    ).toBe("waiting");
    expect(deliveryState(input({ signedIn: false, handed: false })).kind).toBe(
      "waiting",
    );
  });

  it("tells a server copy from one this device last received", () => {
    expect(deliveryState(input({ remote: "server" })).kind).toBe("database");
    expect(deliveryState(input({ remote: "cache" })).kind).toBe("copy");
  });
});
