import { describe, expect, it } from "vitest";
import { debugRows, debugText } from "./debugInfo";

const build = {
  version: "0.1.0",
  sha: "abc1234",
  time: "2027-03-05T18:00:00.000Z",
};
const chromeOnLinux =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";

describe("debugRows", () => {
  it("names the build, platform, browser and connection", () => {
    const rows = debugRows({
      build,
      browser: {
        userAgent: chromeOnLinux,
        maxTouchPoints: 0,
        standalone: true,
      },
      online: false,
    });
    expect(Object.fromEntries(rows)).toEqual({
      "App version": "0.1.0",
      Commit: "abc1234",
      Built: "2027-03-05T18:00:00.000Z",
      Platform: "Linux",
      Browser: "Chrome 130, installed app",
      Connection: "Offline",
    });
  });

  it("says Unknown when the browser reports nothing", () => {
    const rows = Object.fromEntries(
      debugRows({
        build,
        browser: { userAgent: "", maxTouchPoints: 0, standalone: false },
        online: true,
      }),
    );
    expect(rows.Platform).toBe("Unknown");
    expect(rows.Browser).toBe("Unknown");
  });
});

describe("debugText", () => {
  it("writes one label and value per line", () => {
    expect(
      debugText([
        ["A", "1"],
        ["B", "2"],
      ]),
    ).toBe("A: 1\nB: 2");
  });
});
