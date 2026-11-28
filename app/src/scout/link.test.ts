import { describe, expect, it } from "vitest";
import { eventLinkMessage } from "./link";
import type { ScheduledMatch } from "./schedule";

const schedule: ScheduledMatch[] = [
  {
    key: "2027test_qm1",
    compLevel: "qm",
    matchNumber: 1,
    red: [1, 2, 3],
    blue: [4, 5, 6],
  },
];

describe("eventLinkMessage", () => {
  it("says accuracy checks are off with no event", () => {
    expect(eventLinkMessage("", schedule, "1")).toContain("No event selected");
  });

  it("says the schedule has not loaded", () => {
    expect(eventLinkMessage("2027test", [], "1")).toContain("not loaded yet");
  });

  it("asks for a match number", () => {
    expect(eventLinkMessage("2027test", schedule, " ")).toContain(
      "Enter a match number",
    );
  });

  it("says a match that is not in the schedule skips the checks", () => {
    expect(eventLinkMessage("2027test", schedule, "9")).toContain(
      "Match 9 is not in the schedule",
    );
  });

  it("names the key it links to", () => {
    expect(eventLinkMessage("2027test", schedule, "1")).toBe(
      "Scouting at 2027test. This entry links to 2027test_qm1 for accuracy checks.",
    );
  });
});
