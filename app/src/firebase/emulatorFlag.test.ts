import { describe, expect, it } from "vitest";
import { emulatorFlag } from "../../vite.emulators.ts";

describe("emulatorFlag", () => {
  it("is on for a non-production mode that asks for it", () => {
    expect(emulatorFlag("e2e", "true")).toBe("true");
    expect(emulatorFlag("development", "true")).toBe("true");
  });

  it("is always off in a production build", () => {
    expect(emulatorFlag("production", "true")).toBe("false");
  });

  it("is off unless the value is exactly true", () => {
    expect(emulatorFlag("e2e", undefined)).toBe("false");
    expect(emulatorFlag("e2e", "1")).toBe("false");
    expect(emulatorFlag("e2e", "false")).toBe("false");
  });
});
