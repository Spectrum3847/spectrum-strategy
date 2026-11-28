import { describe, expect, it } from "vitest";
import pkg from "../../package.json";
import { packageLicenses } from "./licenses";

describe("packageLicenses", () => {
  it("lists exactly the runtime dependencies", () => {
    expect(Object.keys(packageLicenses).sort()).toEqual(
      Object.keys(pkg.dependencies).sort(),
    );
  });
});
