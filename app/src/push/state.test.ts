import { describe, expect, it } from "vitest";
import { isIos, type PushEnv, pushState, userAgentSummary } from "./state";

const env: PushEnv = {
  ios: false,
  standalone: false,
  hasPush: true,
  permission: "default",
  subscribed: false,
};

describe("pushState", () => {
  it("is off until the person turns it on", () => {
    expect(pushState(env)).toBe("off");
  });

  it("is on only with permission and a subscription", () => {
    expect(pushState({ ...env, permission: "granted", subscribed: true })).toBe(
      "on",
    );
    expect(pushState({ ...env, permission: "granted" })).toBe("off");
    expect(pushState({ ...env, subscribed: true })).toBe("off");
  });

  it("is blocked when permission is denied", () => {
    expect(pushState({ ...env, permission: "denied" })).toBe("denied");
  });

  it("is unsupported without the push APIs", () => {
    expect(pushState({ ...env, hasPush: false })).toBe("unsupported");
  });

  it("sends an iPhone in a Safari tab to the Home Screen steps, even with no push manager there", () => {
    expect(pushState({ ...env, ios: true, hasPush: false })).toBe(
      "needs-home-screen",
    );
  });

  it("treats the Home Screen app on iOS like any browser", () => {
    expect(pushState({ ...env, ios: true, standalone: true })).toBe("off");
    expect(
      pushState({ ...env, ios: true, standalone: true, hasPush: false }),
    ).toBe("unsupported");
  });
});

describe("isIos", () => {
  it("knows iPhone, iPad and an iPad that reports as a Mac", () => {
    expect(isIos("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)", "iPhone", 5)).toBe(
      true,
    );
    expect(isIos("Mozilla/5.0 (iPad; CPU OS 17_0)", "iPad", 5)).toBe(true);
    expect(isIos("Mozilla/5.0 (Macintosh)", "MacIntel", 5)).toBe(true);
  });

  it("does not take a Mac or an Android phone for iOS", () => {
    expect(isIos("Mozilla/5.0 (Macintosh)", "MacIntel", 0)).toBe(false);
    expect(isIos("Mozilla/5.0 (Linux; Android 14)", "Linux armv8l", 5)).toBe(
      false,
    );
  });
});

describe("userAgentSummary", () => {
  it.each([
    [
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1",
      "Safari on iPhone",
    ],
    [
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36",
      "Chrome on Android",
    ],
    [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0 Safari/537.36 Edg/130.0",
      "Edge on Windows",
    ],
    [
      "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0",
      "Firefox on Linux",
    ],
    ["", "Browser on unknown system"],
  ])("summarizes %s", (ua, expected) => {
    expect(userAgentSummary(ua)).toBe(expected);
  });
});
