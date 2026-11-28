import { describe, expect, it } from "vitest";
import { describeTestResponse } from "./testRequest";

describe("describeTestResponse", () => {
  it("says sent, and what to check if nothing shows, when the push service took it", () => {
    const answer = describeTestResponse(200, { ok: true, sent: 1 });
    expect(answer.ok).toBe(true);
    expect(answer.text).toMatch(/Focus or Do Not Disturb/);
  });

  it("tells the person to turn reminders off and on when the push service dropped the device", () => {
    const answer = describeTestResponse(200, { ok: false, sent: 0, gone: 1 });
    expect(answer.ok).toBe(false);
    expect(answer.text).toMatch(/off and on again/);
  });

  it("points to the Outbox when the device is not saved yet", () => {
    expect(
      describeTestResponse(404, { error: "no-subscription" }).text,
    ).toMatch(/Outbox/);
  });

  it("names each other failure", () => {
    expect(describeTestResponse(401, null).text).toMatch(/Sign in again/);
    expect(describeTestResponse(503, null).text).toMatch(/not set up/);
    expect(describeTestResponse(502, null).text).toMatch(/status 502/);
    expect(describeTestResponse(200, null).ok).toBe(false);
  });
});
