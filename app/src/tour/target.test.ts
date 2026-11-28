// @vitest-environment jsdom
import { describe, expect, it } from "vitest";
import {
  type Box,
  boxOf,
  findTarget,
  holePath,
  placeCard,
  sameBox,
  targetKey,
} from "./target";

describe("targetKey", () => {
  const bar = ["/", "/scout", "/teams", "/schedule"];

  it("points at the tab when it is in the bar", () => {
    expect(targetKey("/scout", bar)).toBe("/scout");
    expect(targetKey("nav", bar)).toBe("nav");
  });

  it("points at More when the tab is behind it", () => {
    expect(targetKey("/picks", bar)).toBe("more");
  });

  it("has no target for a step without a nav item", () => {
    expect(targetKey(null, bar)).toBeNull();
  });
});

describe("findTarget", () => {
  it("finds the item by its tour key", () => {
    document.body.innerHTML =
      '<nav><a data-tour-tab="/scout">Scout</a><a data-tour-tab="more">More</a></nav>';
    expect(findTarget(document, "/scout")?.textContent).toBe("Scout");
    expect(findTarget(document, "more")?.textContent).toBe("More");
    expect(findTarget(document, "/picks")).toBeNull();
    expect(findTarget(document, null)).toBeNull();
  });
});

describe("boxOf", () => {
  it("pads the item and ignores one that is not laid out", () => {
    document.body.innerHTML = "<a>x</a>";
    const a = document.querySelector("a");
    expect(boxOf(a)).toBeNull();
    expect(boxOf(null)).toBeNull();
    if (a) {
      a.getBoundingClientRect = () =>
        ({ left: 10, top: 20, width: 50, height: 40 }) as DOMRect;
    }
    expect(boxOf(a)).toEqual({ left: 6, top: 16, width: 58, height: 48 });
  });
});

describe("placeCard", () => {
  const box: Box = { left: 10, top: 600, width: 80, height: 60 };

  it("puts the card above a bottom bar", () => {
    expect(placeCard(box, "bar")).toEqual({ place: "top", clear: 568 });
  });

  it("puts the card right of a rail or sidebar", () => {
    const side: Box = { left: 0, top: 100, width: 88, height: 56 };
    expect(placeCard(side, "rail")).toEqual({ place: "side", clear: 104 });
    expect(placeCard(side, "sidebar")).toEqual({ place: "side", clear: 104 });
  });

  it("keeps the default spot when nothing is highlighted", () => {
    expect(placeCard(null, "bar")).toBeNull();
  });
});

describe("holePath and sameBox", () => {
  it("cuts the box out of the full screen", () => {
    const path = holePath({ left: 1, top: 2, width: 3, height: 4 });
    expect(path).toContain("evenodd");
    expect(path).toContain("1px 2px");
    expect(path).toContain("4px 6px");
  });

  it("compares boxes by value", () => {
    const a: Box = { left: 1, top: 2, width: 3, height: 4 };
    expect(sameBox(a, { ...a })).toBe(true);
    expect(sameBox(a, { ...a, top: 3 })).toBe(false);
    expect(sameBox(a, null)).toBe(false);
    expect(sameBox(null, null)).toBe(true);
  });
});
