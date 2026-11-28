// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { InstallBanner } from "./InstallBanner";

const device = vi.hoisted(() => ({
  current: {
    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)",
    platform: "iPhone",
    maxTouchPoints: 5,
    standalone: false,
  },
}));
vi.mock("./installPrompt", async (original) => ({
  ...(await original<typeof import("./installPrompt")>()),
  currentDevice: () => device.current,
}));

afterEach(() => {
  cleanup();
  localStorage.clear();
  device.current = {
    ...device.current,
    userAgent: "iPhone",
    standalone: false,
  };
});

describe("InstallBanner", () => {
  it("says why and how, and can be dismissed for a while", () => {
    render(<InstallBanner />);
    expect(screen.getByText(/shift reminders only work/)).toBeTruthy();
    expect(screen.getByText(/Choose Add to Home Screen/)).toBeTruthy();
    fireEvent.click(screen.getByRole("button", { name: "Not now" }));
    expect(screen.queryByRole("region")).toBeNull();
    expect(
      Number(localStorage.getItem("ss.install.dismissed")),
    ).toBeGreaterThan(0);
    cleanup();
    render(<InstallBanner />);
    expect(screen.queryByText(/Home Screen/)).toBeNull();
  });

  it("is absent in standalone mode", () => {
    device.current = { ...device.current, standalone: true };
    render(<InstallBanner />);
    expect(screen.queryByText(/Home Screen/)).toBeNull();
  });

  it("is absent on a desktop", () => {
    device.current = {
      userAgent: "Mozilla/5.0 (X11; Linux x86_64)",
      platform: "Linux x86_64",
      maxTouchPoints: 0,
      standalone: false,
    };
    render(<InstallBanner />);
    expect(screen.queryByText(/Home Screen/)).toBeNull();
  });
});
