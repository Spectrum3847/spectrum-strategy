import { describe, expect, it } from "vitest";
import { bundled, fieldFor, loadFields } from "./field";

const manifest = {
  latest: "2027-next",
  fields: [
    { id: "2026-old", json: "assets/fields/wpilib/2026-old.json" },
    { id: "2027-next", json: "assets/fields/wpilib/2027-next.json" },
    { id: "2028-gone", json: "assets/fields/wpilib/2028-gone.json" },
  ],
};

const file = (game: string, image: string, size: number[]) => ({
  game,
  "field-image": image,
  "field-size": size,
});

describe("loadFields", () => {
  const found = loadFields(
    {
      "/a/MANIFEST.json": manifest,
      "/a/2026-old.json": file("Old", "2026-old.png", [54, 27]),
      "/a/2027-next.json": file("Next", "2027-next.jpg", [60, 30]),
      "/a/2028-gone.json": file("Gone", "2028-gone.png", [60, 30]),
    },
    { "/a/2026-old.png": "/old.png", "/a/2027-next.jpg": "/next.jpg" },
  );

  it("takes the aspect from the field size and follows the manifest", () => {
    expect(found.latest).toBe("2027-next");
    expect(found.fields.map((f) => f.id)).toEqual(["2026-old", "2027-next"]);
    expect(found.fields[1]).toEqual({
      id: "2027-next",
      game: "Next",
      image: "/next.jpg",
      aspect: 2,
    });
  });

  it("skips a field whose image is not bundled", () => {
    expect(found.fields.some((f) => f.id === "2028-gone")).toBe(false);
  });

  it("uses the newest id when the manifest names none", () => {
    const none = loadFields(
      {
        "/a/MANIFEST.json": { fields: manifest.fields.slice(0, 2) },
        "/a/2026-old.json": file("Old", "2026-old.png", [54, 27]),
        "/a/2027-next.json": file("Next", "2027-next.jpg", [60, 30]),
      },
      { "/a/2026-old.png": "/old.png", "/a/2027-next.jpg": "/next.jpg" },
    );
    expect(none.latest).toBe("2027-next");
  });

  it("falls back to the current field for a dropped season", () => {
    expect(fieldFor(found, "2026-old")?.id).toBe("2026-old");
    expect(fieldFor(found, "1999-lost")?.id).toBe("2027-next");
    expect(fieldFor({ fields: [], latest: "" }, "x")).toBeNull();
  });
});

describe("bundled", () => {
  it("has the current field from the repo root", () => {
    const field = fieldFor(bundled, bundled.latest);
    expect(field?.game).toMatch(/FRC/);
    expect(field?.aspect).toBeCloseTo(54.269 / 26.474, 3);
    expect(field?.image).toMatch(/\.(png|jpe?g|webp)/);
  });
});
