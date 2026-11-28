import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  bugReportDoc,
  environment,
  maxBody,
  maxScreenshots,
  maxTitle,
  rolesLabel,
} from "./bugReport";

const root = (path: string) =>
  readFileSync(new URL(`../../../${path}`, import.meta.url), "utf8");

function ruleKeys(fn: string): string[] {
  const rules = root("firestore.rules");
  const body = rules.slice(rules.indexOf(`function ${fn}(`));
  const list = /hasOnly\(\[([^\]]*)\]\)/.exec(body)?.[1] ?? "";
  return [...list.matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");
}

const build = {
  version: "0.1.0",
  sha: "abc1234",
  time: "2027-03-01T10:00:00.000Z",
};
const ipadUa =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";
const env = environment(build, {
  userAgent: ipadUa,
  maxTouchPoints: 5,
  standalone: true,
});
const reporter = { uid: "u1", name: "Scout A", roles: ["scouter" as const] };
const now = new Date("2027-03-01T10:00:00.000Z");
const full = {
  kind: "bug" as const,
  area: "Strategy board",
  impact: "Cosmetic issue",
  title: "  Board did not save  ",
  body: "  It stayed blank.  ",
};

describe("bugReportDoc", () => {
  it("writes the report document", () => {
    expect(bugReportDoc(full, reporter, env, "id1", now)).toEqual({
      id: "id1",
      title: "Board did not save",
      body: "It stayed blank.",
      reporterUid: "u1",
      reporterName: "Scout A",
      roles: "Scouter",
      kind: "bug",
      area: "Strategy board",
      impact: "Cosmetic issue",
      appVersion: "0.1.0 (abc1234 2027-03-01)",
      platform: "web",
      osVersion: "iPadOS",
      deviceInfo: "Safari 17, installed app",
      status: "new",
      createdAt: "2027-03-01T10:00:00.000Z",
    });
  });

  it("writes only keys the rules allow", () => {
    const keys = Object.keys(bugReportDoc(full, reporter, env, "id1", now));
    const rules = ruleKeys("isValidBugReport");
    for (const key of keys) expect(rules).toContain(key);
  });

  it("adds the screenshot keys when some uploaded, at most three", () => {
    const doc = bugReportDoc(
      { ...full, screenshotKeys: ["a.jpg", "b.jpg", "c.jpg", "d.jpg"] },
      reporter,
      env,
      "id1",
      now,
    );
    expect(doc.screenshotKeys).toEqual(["a.jpg", "b.jpg", "c.jpg"]);
    expect(ruleKeys("isValidBugReport")).toContain("screenshotKeys");
  });

  it("leaves screenshotKeys out when none uploaded", () => {
    const doc = bugReportDoc(
      { ...full, screenshotKeys: [] },
      reporter,
      env,
      "id1",
      now,
    );
    expect("screenshotKeys" in doc).toBe(false);
  });

  it("leaves out an empty area, an empty impact and no roles", () => {
    const doc = bugReportDoc(
      { ...full, area: "", impact: "" },
      { ...reporter, roles: [] },
      env,
      "id1",
      now,
    );
    for (const key of ["area", "impact", "roles", "screenshotKeys"]) {
      expect(key in doc).toBe(false);
    }
  });

  it("sends no impact with feedback", () => {
    const doc = bugReportDoc(
      { ...full, kind: "feedback" },
      reporter,
      env,
      "id1",
      now,
    );
    expect(doc.kind).toBe("feedback");
    expect("impact" in doc).toBe(false);
  });

  it("clamps to the rules limits", () => {
    const doc = bugReportDoc(
      {
        ...full,
        title: "t".repeat(500),
        body: "b".repeat(9000),
      },
      { uid: "u".repeat(300), name: "n".repeat(300), roles: [] },
      env,
      "id1",
      now,
    );
    expect(String(doc.title)).toHaveLength(maxTitle);
    expect(String(doc.body)).toHaveLength(maxBody);
    expect(String(doc.reporterUid)).toHaveLength(128);
    expect(String(doc.reporterName)).toHaveLength(128);
  });

  it("names an unnamed reporter Unknown", () => {
    const doc = bugReportDoc(full, { ...reporter, name: "" }, env, "id1", now);
    expect(doc.reporterName).toBe("Unknown");
  });

  it("starts with status new and an ISO createdAt", () => {
    const doc = bugReportDoc(full, reporter, env, "id1", now);
    expect(doc.status).toBe("new");
    expect(String(doc.createdAt).length).toBeGreaterThanOrEqual(20);
  });
});

describe("rules limits", () => {
  const rules = root("firestore.rules");
  const body = rules.slice(rules.indexOf("function isValidBugReport("));

  it("matches the title, body and screenshot bounds", () => {
    expect(body).toContain(`data.title.size() <= ${maxTitle}`);
    expect(body).toContain(`data.body.size() <= ${maxBody}`);
    expect(body).toContain(`data.screenshotKeys.size() <= ${maxScreenshots}`);
  });
});

describe("environment", () => {
  const at = (userAgent: string, maxTouchPoints = 0, standalone = false) =>
    environment(build, { userAgent, maxTouchPoints, standalone });

  it("reads an iPhone", () => {
    const e = at(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1",
      5,
    );
    expect(e.osVersion).toBe("iOS 17.4");
    expect(e.deviceInfo).toBe("Safari 17");
  });

  it("reads Chrome on Android", () => {
    const e = at(
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36",
      5,
    );
    expect(e.osVersion).toBe("Android 14");
    expect(e.deviceInfo).toBe("Chrome 124");
  });

  it("tells Edge from Chrome and a Mac from an iPad", () => {
    const e = at(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0",
    );
    expect(e.osVersion).toBe("Windows");
    expect(e.deviceInfo).toBe("Edge 124");
    expect(at(ipadUa, 0).osVersion).toBe("macOS");
    expect(at(ipadUa, 5).osVersion).toBe("iPadOS");
  });

  it("falls back when the agent says nothing useful", () => {
    const e = at("");
    expect(e.osVersion).toBe("");
    expect(e.deviceInfo).toBe("Unknown browser");
    expect(e.platform).toBe("web");
  });

  it("builds the version label from the build", () => {
    expect(env.appVersion).toBe("0.1.0 (abc1234 2027-03-01)");
  });
});

describe("rolesLabel", () => {
  it("sorts display names in role order", () => {
    expect(rolesLabel(["strategy", "admin", "scouter"])).toBe(
      "Admin, Scouter, Strategist",
    );
    expect(rolesLabel(["mentor", "scouter"])).toBe("Mentor, Scouter");
    expect(rolesLabel([])).toBe("");
  });
});
