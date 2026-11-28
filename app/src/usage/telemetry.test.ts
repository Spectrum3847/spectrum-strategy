import { readFileSync } from "node:fs";
import { describe, expect, it, vi } from "vitest";
import {
  createTelemetry,
  createTracker,
  type Env,
  screenName,
  type TelemetryDeps,
  telemetryEvent,
} from "./telemetry";

const rules = readFileSync(
  new URL("../../../firestore.rules", import.meta.url),
  "utf8",
);
const body = rules.slice(rules.indexOf("function isValidTelemetry("));
const fn = body.slice(0, body.indexOf("\n    }\n"));
const allowed = [
  ...(/hasOnly\(\[([^\]]*)\]\)/.exec(fn)?.[1] ?? "").matchAll(/'([^']+)'/g),
].map((m) => m[1] ?? "");
const limits: Record<string, number> = Object.fromEntries(
  [...fn.matchAll(/data\.(\w+)\.size\(\) <= (\d+)/g)].map((m) => [
    m[1],
    Number(m[2]),
  ]),
);
const required = [...fn.matchAll(/&& data\.(\w+) is string/g)].map(
  (m) => m[1] ?? "",
);

const env: Env = {
  appVersion: "0.1.0 (abc1234 2027-01-02)",
  platform: "web",
  osVersion: "",
  locale: "en-US",
};
const at = new Date("2027-03-04T05:06:07.890Z");

describe("telemetryEvent", () => {
  it("uses only the keys the rules allow", () => {
    expect(allowed).toContain("deviceId");
    const data = telemetryEvent("tab_open", "Scout", "e1", "d1", env, at);
    for (const key of Object.keys(data)) expect(allowed).toContain(key);
    for (const key of required) expect(data).toHaveProperty(key);
  });

  it("clamps every value to the rules' limits", () => {
    const long = "x".repeat(500);
    const data = telemetryEvent(
      long,
      long,
      "e1",
      "d1",
      { appVersion: long, platform: long, osVersion: long, locale: long },
      at,
    );
    for (const [key, max] of Object.entries(limits)) {
      expect((data[key] ?? "").length, key).toBeLessThanOrEqual(max);
    }
  });

  it("stamps a UTC ISO time the rules accept", () => {
    const data = telemetryEvent("app_open", undefined, "e1", "d1", env, at);
    const stamp = data.createdAt ?? "";
    expect(stamp).toBe("2027-03-04T05:06:07.890Z");
    expect(stamp.length).toBeGreaterThanOrEqual(20);
    expect(stamp >= "2020" && stamp < "2100").toBe(true);
    expect(data).not.toHaveProperty("detail");
  });

  it("leaves out an empty locale", () => {
    const data = telemetryEvent(
      "app_open",
      "",
      "e1",
      "d1",
      { ...env, locale: "" },
      at,
    );
    expect(data).not.toHaveProperty("locale");
    expect(data).not.toHaveProperty("detail");
  });
});

function setup(over: Partial<TelemetryDeps> = {}) {
  const write = vi.fn((_id: string, _data: Record<string, string>) =>
    Promise.resolve(),
  );
  const telemetry = createTelemetry({
    enabled: () => true,
    suppressed: () => false,
    deviceId: () => "device-1",
    env: () => env,
    write,
    now: () => at,
    newId: () => "event-1",
    ...over,
  });
  return { telemetry, write };
}

describe("createTelemetry", () => {
  it("writes one event to telemetry/{id}", () => {
    const { telemetry, write } = setup();
    telemetry.log("tab_open", "Scout");
    expect(write).toHaveBeenCalledTimes(1);
    expect(write.mock.calls[0]?.[0]).toBe("event-1");
    expect(write.mock.calls[0]?.[1]).toMatchObject({
      id: "event-1",
      type: "tab_open",
      detail: "Scout",
      deviceId: "device-1",
      platform: "web",
    });
  });

  it("sends nothing when the switch is off", () => {
    const { telemetry, write } = setup({ enabled: () => false });
    telemetry.log("app_open");
    expect(write).not.toHaveBeenCalled();
  });

  it("sends nothing in training or the emulator harness", () => {
    const { telemetry, write } = setup({ suppressed: () => true });
    telemetry.log("app_open");
    expect(write).not.toHaveBeenCalled();
  });

  it("swallows a failed or throwing write", async () => {
    const failing = setup({ write: () => Promise.reject(new Error("denied")) });
    expect(() => failing.telemetry.log("app_open")).not.toThrow();
    const throwing = setup({
      write: () => {
        throw new Error("boom");
      },
    });
    expect(() => throwing.telemetry.log("app_open")).not.toThrow();
    await Promise.resolve();
  });
});

describe("screenName", () => {
  it("maps web routes to the stored tab names", () => {
    expect(screenName("/")).toBe("Now");
    expect(screenName("/scout/pit/1111")).toBe("Scout");
    expect(screenName("/teams/compare")).toBe("Prematch");
    expect(screenName("/matches/2027test_qm1")).toBe("Strategy");
    expect(screenName("/help/scouting")).toBe("Docs");
    expect(screenName("/usage")).toBe("Usage");
    expect(screenName("/scoutx")).toBeNull();
    expect(screenName("/nowhere")).toBeNull();
  });
});

describe("createTracker", () => {
  it("opens once, then logs only a change of tab", () => {
    const log = vi.fn();
    const tracker = createTracker(log);
    tracker.visit("/");
    tracker.visit("/");
    tracker.visit("/scout");
    tracker.visit("/scout/pit");
    tracker.visit("/teams/1111");
    tracker.visit("/nowhere");
    tracker.visit("/scout");
    expect(log.mock.calls).toEqual([
      ["app_open"],
      ["tab_open", "Scout"],
      ["tab_open", "Prematch"],
      ["tab_open", "Scout"],
    ]);
  });

  it("counts a launch straight into another tab", () => {
    const log = vi.fn();
    createTracker(log).visit("/schedule");
    expect(log.mock.calls).toEqual([["app_open"], ["tab_open", "Schedule"]]);
  });
});
