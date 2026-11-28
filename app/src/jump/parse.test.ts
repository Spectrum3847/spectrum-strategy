import { describe, expect, it } from "vitest";
import { type JumpContext, parseMatchQuery, resolveJump } from "./parse";

describe("parseMatchQuery", () => {
  it.each([
    ["q45", "qm45", "Qualification 45"],
    ["qm45", "qm45", "Qualification 45"],
    ["Q 45", "qm45", "Qualification 45"],
    ["m7", "qm7", "Qualification 7"],
    ["match12", "qm12", "Qualification 12"],
    ["sf2", "sf2m1", "Semifinal 2"],
    ["sf2m1", "sf2m1", "Semifinal 2 match 1"],
    ["SF-3m2", "sf3m2", "Semifinal 3 match 2"],
    ["f1m2", "f1m2", "Final 1 match 2"],
    ["f1", "f1m1", "Final 1"],
  ])("reads %s", (text, suffix, label) => {
    expect(parseMatchQuery(text)).toEqual({ suffix, label });
  });

  it.each(["3847", "frc3847", "", "q", "q0", "sf0", "sf1m0", "x45", "qm"])(
    "does not read %j as a match",
    (text) => {
      expect(parseMatchQuery(text)).toBeNull();
    },
  );
});

describe("resolveJump", () => {
  const ctx: JumpContext = {
    eventKey: "2027test",
    knownTeams: new Set([1111, 2222]),
    matchKeys: ["2027test_qm45", "2027test_sf2m1"],
    canTeam: true,
    canMatch: true,
  };

  it("opens a team at the event", () => {
    expect(resolveJump("1111", ctx)).toMatchObject({
      ok: true,
      path: "/teams/1111",
    });
    expect(resolveJump("frc2222", ctx)).toMatchObject({ path: "/teams/2222" });
  });

  it("opens any team while no team list is loaded", () => {
    expect(
      resolveJump("9999", { ...ctx, knownTeams: new Set() }),
    ).toMatchObject({ ok: true, path: "/teams/9999" });
  });

  it("refuses a team that is not at the event", () => {
    expect(resolveJump("9999", ctx)).toEqual({
      ok: false,
      message: "Team 9999 is not at this event.",
    });
  });

  it("opens a match in the schedule", () => {
    expect(resolveJump("q45", ctx)).toMatchObject({
      ok: true,
      kind: "match",
      path: "/matches/2027test_qm45",
    });
    expect(resolveJump("SF2M1", ctx)).toMatchObject({
      path: "/matches/2027test_sf2m1",
    });
  });

  it("says when a match is not in the schedule or no event is set", () => {
    expect(resolveJump("q99", ctx)).toEqual({
      ok: false,
      message: "Qualification 99 is not in the schedule.",
    });
    expect(resolveJump("q45", { ...ctx, eventKey: "" })).toMatchObject({
      ok: false,
      message: expect.stringContaining("No event"),
    });
  });

  it("refuses what the role cannot open", () => {
    expect(resolveJump("1111", { ...ctx, canTeam: false })).toMatchObject({
      ok: false,
      message: "Your role cannot open team pages.",
    });
    expect(resolveJump("q45", { ...ctx, canMatch: false })).toMatchObject({
      ok: false,
      message: "Your role cannot open match pages.",
    });
  });

  it("asks for a team or match when the text is neither", () => {
    expect(resolveJump("hello", ctx)).toMatchObject({
      ok: false,
      message: "Enter a team number like 3847 or a match like q45.",
    });
  });
});
