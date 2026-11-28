import { describe, expect, it } from "vitest";
import { parseConfig, type ScoutField } from "../scout/config";
import {
  blankCell,
  cellKind,
  editText,
  isReadOnly,
  parseCell,
} from "./cellValue";

const config = parseConfig({
  title: "t",
  sections: [
    {
      name: "s",
      fields: [
        { title: "Scouter", code: "scouter", type: "text" },
        {
          title: "Robot",
          code: "robot",
          type: "select",
          choices: { R1: "R1", B2: "B2" },
        },
        { title: "Team", code: "pTnumber", type: "number", min: 1, max: 19999 },
        { title: "Count", code: "count", type: "counter" },
        { title: "Rating", code: "rating", type: "range", min: 1, max: 5 },
        { title: "Qty", code: "qty", type: "number" },
        { title: "Flag", code: "flag", type: "boolean" },
        {
          title: "Climb",
          code: "climb",
          type: "select",
          choices: { N: "None", L1: "Level 1" },
        },
        {
          title: "Skills",
          code: "skills",
          type: "checkboxSelect",
          choices: { a: "A", b: "B" },
        },
        { title: "Notes", code: "notes", type: "longText" },
      ],
    },
  ],
});

const field = (code: string): ScoutField => {
  const f = config.sections[0]?.fields.find((x) => x.code === code);
  if (!f) throw new Error(code);
  return f;
};

describe("parseCell", () => {
  it("takes a counter as a whole number of at least zero", () => {
    expect(parseCell(field("count"), "7")).toEqual({ ok: true, value: 7 });
    expect(parseCell(field("count"), "-1").ok).toBe(false);
    expect(parseCell(field("count"), "2.5").ok).toBe(false);
    expect(parseCell(field("count"), "abc").ok).toBe(false);
    expect(parseCell(field("count"), "").ok).toBe(false);
  });

  it("keeps a rating inside its range", () => {
    expect(parseCell(field("rating"), "5")).toEqual({ ok: true, value: 5 });
    expect(parseCell(field("rating"), "6").ok).toBe(false);
    expect(parseCell(field("rating"), "0").ok).toBe(false);
  });

  it("stores a number field as text, and allows it blank", () => {
    expect(parseCell(field("qty"), " 12 ")).toEqual({ ok: true, value: "12" });
    expect(parseCell(field("qty"), "")).toEqual({ ok: true, value: "" });
    expect(parseCell(field("qty"), "-3").ok).toBe(false);
  });

  it("accepts only a configured choice", () => {
    expect(parseCell(field("climb"), "L1")).toEqual({ ok: true, value: "L1" });
    expect(parseCell(field("climb"), "L9").ok).toBe(false);
    expect(parseCell(field("climb"), "")).toEqual({ ok: true, value: "" });
  });

  it("joins a multi choice and refuses an unknown one", () => {
    expect(parseCell(field("skills"), "a,b")).toEqual({
      ok: true,
      value: "a,b",
    });
    expect(parseCell(field("skills"), "a,z").ok).toBe(false);
  });

  it("passes text through", () => {
    expect(parseCell(field("notes"), "fast")).toEqual({
      ok: true,
      value: "fast",
    });
  });
});

describe("blankCell", () => {
  it("clears text and choices but not a counter or a yes/no", () => {
    expect(blankCell(field("notes"))).toEqual({ ok: true, value: "" });
    expect(blankCell(field("climb"))).toEqual({ ok: true, value: "" });
    expect(blankCell(field("count")).ok).toBe(false);
    expect(blankCell(field("flag")).ok).toBe(false);
  });
});

describe("isReadOnly", () => {
  it("locks the team, the scout and the station", () => {
    expect(isReadOnly(field("pTnumber"))).toBe(true);
    expect(isReadOnly(field("scouter"))).toBe(true);
    expect(isReadOnly(field("robot"))).toBe(true);
    expect(isReadOnly(field("count"))).toBe(false);
    expect(isReadOnly(field("climb"))).toBe(false);
  });
});

describe("cell kinds and edit text", () => {
  it("maps field types to editors", () => {
    expect(cellKind(field("skills"))).toBe("multi");
    expect(cellKind(field("flag"))).toBe("boolean");
    expect(cellKind(field("climb"))).toBe("select");
  });

  it("starts a select on its stored key and a number on its text", () => {
    expect(editText(field("climb"), "Level 1")).toBe("L1");
    expect(editText(field("count"), 4)).toBe("4");
    expect(editText(field("count"), undefined)).toBe("");
  });
});
