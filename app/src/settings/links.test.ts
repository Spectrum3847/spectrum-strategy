import { describe, expect, it } from "vitest";
import { creditLinks, sourceLinks } from "./links";

describe("links", () => {
  it("are all https and open outside the app", () => {
    for (const link of [...creditLinks, ...sourceLinks]) {
      expect(new URL(link.url).protocol).toBe("https:");
    }
  });

  it("point the repo docs at the public mirror", () => {
    for (const link of sourceLinks) {
      expect(link.url).toContain("github.com/Spectrum3847/spectrum-strategy");
    }
  });
});
