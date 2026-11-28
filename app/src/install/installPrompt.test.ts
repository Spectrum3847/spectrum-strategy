// @vitest-environment jsdom
import { afterEach, describe, expect, it } from "vitest";
import {
  type Device,
  dismissDays,
  isIos,
  readDismissed,
  showInstallPrompt,
  writeDismissed,
} from "./installPrompt";

const iphone: Device = {
  userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
  platform: "iPhone",
  maxTouchPoints: 5,
  standalone: false,
};
const ipadAsMac: Device = {
  userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
  platform: "MacIntel",
  maxTouchPoints: 5,
  standalone: false,
};
const mac: Device = { ...ipadAsMac, maxTouchPoints: 0 };
const android: Device = {
  userAgent: "Mozilla/5.0 (Linux; Android 15; Pixel 9)",
  platform: "Linux armv8l",
  maxTouchPoints: 5,
  standalone: false,
};
const day = 24 * 60 * 60 * 1000;

describe("isIos", () => {
  it("knows iPhone, iPad and an iPad that reports as a Mac", () => {
    expect(isIos(iphone)).toBe(true);
    expect(
      isIos({ ...iphone, userAgent: "Mozilla/5.0 (iPad; CPU OS 18_0)" }),
    ).toBe(true);
    expect(isIos(ipadAsMac)).toBe(true);
  });

  it("does not take a real Mac or Android", () => {
    expect(isIos(mac)).toBe(false);
    expect(isIos(android)).toBe(false);
  });
});

describe("showInstallPrompt", () => {
  it("shows on iOS in a browser tab", () => {
    expect(showInstallPrompt(iphone, null, 0)).toBe(true);
    expect(showInstallPrompt(ipadAsMac, null, 0)).toBe(true);
  });

  it("never shows in standalone, on desktop or on Android", () => {
    expect(showInstallPrompt({ ...iphone, standalone: true }, null, 0)).toBe(
      false,
    );
    expect(showInstallPrompt(mac, null, 0)).toBe(false);
    expect(showInstallPrompt(android, null, 0)).toBe(false);
  });

  it("stays hidden for the dismissal window, then returns", () => {
    const at = 1_000_000;
    expect(showInstallPrompt(iphone, at, at + 1)).toBe(false);
    expect(showInstallPrompt(iphone, at, at + dismissDays * day - 1)).toBe(
      false,
    );
    expect(showInstallPrompt(iphone, at, at + dismissDays * day)).toBe(true);
  });
});

describe("dismissal storage", () => {
  afterEach(() => localStorage.clear());

  it("round trips and ignores junk", () => {
    expect(readDismissed()).toBeNull();
    writeDismissed(1234);
    expect(readDismissed()).toBe(1234);
    localStorage.setItem("ss.install.dismissed", "soon");
    expect(readDismissed()).toBeNull();
  });
});
