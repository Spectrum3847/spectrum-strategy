// @vitest-environment jsdom
import { describe, expect, it, vi } from "vitest";
import {
  boardTitle,
  type Ctx,
  deliverImage,
  drawBoard,
  exportFileName,
  imageLayout,
  outputWidth,
  wrapLines,
} from "./exportImage";
import { newSession, penColor, perPhase } from "./model";

describe("names", () => {
  it("titles a match with or without an event name", () => {
    expect(boardTitle({ eventName: "", matchNumber: 7 })).toBe("Match 7");
    expect(boardTitle({ eventName: " Test Regional ", matchNumber: 7 })).toBe(
      "Test Regional - Match 7",
    );
  });

  it("makes a safe file name with the phase", () => {
    expect(exportFileName("Test Regional - Match 7", "teleop")).toBe(
      "test_regional_match_7_teleop.png",
    );
    expect(exportFileName("  !!  ", "auton")).toBe("strategy_match_auton.png");
  });
});

describe("layout", () => {
  it("keeps the field's aspect under the header and legend", () => {
    const l = imageLayout(2);
    expect(l.width).toBe(outputWidth);
    expect(l.fieldHeight).toBe(500);
    expect(l.fieldTop).toBe(120);
    expect(l.height).toBe(Math.round((120 + 500) * l.scale));
  });

  it("falls back to 2 for a bad aspect", () => {
    expect(imageLayout(0).fieldHeight).toBe(500);
  });
});

describe("wrapLines", () => {
  const measure = (s: string) => s.length * 10;
  it("wraps at the width and keeps long words whole", () => {
    expect(wrapLines("aa bb cc dd", 50, measure)).toEqual(["aa bb", "cc dd"]);
    expect(wrapLines("abcdefghij kl", 50, measure)).toEqual([
      "abcdefghij",
      "kl",
    ]);
    expect(wrapLines("  ", 50, measure)).toEqual([]);
  });
});

function fakeCtx() {
  const calls: string[] = [];
  const text: string[] = [];
  const handler = {
    get(target: Record<string, unknown>, key: string) {
      if (key in target) return target[key];
      if (key === "measureText")
        return (s: string) => ({ width: s.length * 7 });
      if (key === "fillText") {
        return (s: string) => {
          text.push(s);
        };
      }
      return () => {
        calls.push(key);
      };
    },
    set(target: Record<string, unknown>, key: string, value: unknown) {
      target[key] = value;
      return true;
    },
  };
  return { ctx: new Proxy({}, handler) as unknown as Ctx, calls, text };
}

describe("drawBoard", () => {
  const session = newSession({
    id: "b1",
    eventKey: "2027test",
    matchNumber: 3,
    alliance: "Red",
    teamNumbers: [1111],
    fieldId: "f",
    author: { uid: "u", displayName: "Lead A" },
    nowMs: 0,
  });
  session.eventName = "Test Regional";
  session.strokes.teleop = [
    {
      phase: "teleop",
      legend: false,
      color: penColor,
      points: [
        { x: 0.1, y: 0.1 },
        { x: 0.5, y: 0.5 },
      ],
    },
  ];
  session.markers.teleop = [
    {
      phase: "teleop",
      position: { x: 0.3, y: 0.3 },
      team: 1111,
      label: null,
      alliance: "Red",
    },
  ];
  session.labels.teleop = [{ x: 0.6, y: 0.6, text: "Defend" }];

  it("writes the title, phase, markers and labels", () => {
    const { ctx, calls, text } = fakeCtx();
    const layout = drawBoard(
      ctx,
      {
        title: "Test Regional - Match 3",
        phase: "teleop",
        aspect: 2,
        strokes: session.strokes.teleop,
        markers: session.markers.teleop,
        labels: session.labels.teleop,
        sideOf: () => "red",
      },
      null,
    );
    expect(layout.width).toBe(outputWidth);
    expect(text).toEqual(
      expect.arrayContaining([
        "Test Regional - Match 3",
        "Teleop",
        "1111",
        "R",
        "Defend",
      ]),
    );
    expect(calls).toContain("stroke");
  });

  it("draws an empty phase", () => {
    const { ctx, text } = fakeCtx();
    drawBoard(
      ctx,
      {
        title: "Match 1",
        phase: "auton",
        aspect: 2,
        strokes: [],
        markers: [],
        labels: [],
        sideOf: () => "blue",
      },
      null,
    );
    expect(text).toEqual(["Match 1", "Auto"]);
    expect(perPhase(() => 0).auton).toBe(0);
  });
});

describe("deliverImage", () => {
  const blob = new Blob(["x"], { type: "image/png" });

  it("shares a file when the browser can", async () => {
    const share = vi.fn(async () => undefined);
    const save = vi.fn();
    const out = await deliverImage(
      blob,
      "a.png",
      "Match 1",
      { canShare: () => true, share },
      save,
    );
    expect(out).toBe("shared");
    expect(share).toHaveBeenCalledOnce();
    expect(save).not.toHaveBeenCalled();
  });

  it("downloads when files cannot be shared", async () => {
    const save = vi.fn();
    const out = await deliverImage(
      blob,
      "a.png",
      "Match 1",
      { canShare: () => false, share: vi.fn() },
      save,
    );
    expect(out).toBe("downloaded");
    expect(save).toHaveBeenCalledWith(blob, "a.png");
  });

  it("downloads when there is no share API", async () => {
    const save = vi.fn();
    expect(await deliverImage(blob, "a.png", "t", {}, save)).toBe("downloaded");
  });

  it("does nothing more when the share sheet is cancelled", async () => {
    const save = vi.fn();
    const share = vi.fn(async () => {
      throw new DOMException("cancelled", "AbortError");
    });
    const out = await deliverImage(
      blob,
      "a.png",
      "t",
      { canShare: () => true, share },
      save,
    );
    expect(out).toBe("cancelled");
    expect(save).not.toHaveBeenCalled();
  });

  it("downloads when sharing fails for another reason", async () => {
    const save = vi.fn();
    const share = vi.fn(async () => {
      throw new DOMException("no", "NotAllowedError");
    });
    const out = await deliverImage(
      blob,
      "a.png",
      "t",
      { canShare: () => true, share },
      save,
    );
    expect(out).toBe("downloaded");
    expect(save).toHaveBeenCalled();
  });
});
