import type { Role } from "../auth/roles";

export const kinds = ["bug", "feedback"] as const;
export type Kind = (typeof kinds)[number];

export const kindLabels: Record<Kind, string> = {
  bug: "Bug",
  feedback: "Feedback",
};

export const areas = [
  "Strategy board",
  "Scouting capture / QR",
  "Pit scouting",
  "Firebase sync",
  "Prematch (event team list, EPA/rank)",
  "Team compare",
  "Playoff ranking",
  "Schedule / shifts",
  "AI assistant / MCP",
  "Roles / permissions",
  "Auth / sign-in",
  "Theme / Liquid Glass design",
  "Web build / offline support",
  "Build, CI, or release tooling",
  "Docs",
  "Other",
  "Not sure",
] as const;

export const impacts = [
  "Blocks work completely",
  "Major degradation or frequent failure",
  "Minor bug or occasional failure",
  "Cosmetic issue",
] as const;

export const maxTitle = 200;
export const maxBody = 4096;
export const maxScreenshots = 3;

const roleNames: Record<Role, string> = {
  viewer: "Viewer",
  scouter: "Scouter",
  strategy: "Strategist",
  admin: "Admin",
  developer: "Developer",
  mentor: "Mentor",
};

export const rolesLabel = (roles: Role[]) =>
  roles
    .map((r) => roleNames[r])
    .sort()
    .join(", ");

const clamp = (value: string, max: number) =>
  value.length <= max ? value : value.slice(0, max);

export interface Environment {
  appVersion: string;
  platform: string;
  osVersion: string;
  deviceInfo: string;
}

interface Browser {
  userAgent: string;
  maxTouchPoints: number;
  standalone: boolean;
}

function osOf(ua: string, touch: number): string {
  const ios = /(?:iPhone|CPU) OS (\d+(?:_\d+)*)/.exec(ua);
  if (/iPhone|iPad|iPod/.test(ua) && ios?.[1]) {
    return `iOS ${ios[1].replaceAll("_", ".")}`;
  }
  const android = /Android (\d+(?:\.\d+)*)/.exec(ua);
  if (android?.[1]) return `Android ${android[1]}`;
  if (/Windows NT/.test(ua)) return "Windows";
  if (/Macintosh/.test(ua)) return touch > 1 ? "iPadOS" : "macOS";
  if (/CrOS/.test(ua)) return "ChromeOS";
  if (/Linux/.test(ua)) return "Linux";
  return "";
}

const browsers: [RegExp, string][] = [
  [/Edg\/(\d+)/, "Edge"],
  [/OPR\/(\d+)/, "Opera"],
  [/(?:CriOS|Chrome)\/(\d+)/, "Chrome"],
  [/(?:FxiOS|Firefox)\/(\d+)/, "Firefox"],
  [/Version\/(\d+).*Safari/, "Safari"],
];

function browserOf(ua: string): string {
  for (const [pattern, name] of browsers) {
    const major = pattern.exec(ua)?.[1];
    if (major) return `${name} ${major}`;
  }
  return "Unknown browser";
}

export function environment(
  build: { version: string; sha: string; time: string },
  browser: Browser,
): Environment {
  const { userAgent: ua } = browser;
  return {
    appVersion: clamp(
      `${build.version} (${build.sha} ${build.time.slice(0, 10)})`,
      64,
    ),
    platform: "web",
    osVersion: clamp(osOf(ua, browser.maxTouchPoints), 128),
    deviceInfo: clamp(
      `${browserOf(ua)}${browser.standalone ? ", installed app" : ""}`,
      256,
    ),
  };
}

export interface ReportInput {
  kind: Kind;
  area: string;
  impact: string;
  title: string;
  body: string;
  screenshotKeys?: string[];
}

export interface Reporter {
  uid: string;
  name: string;
  roles: Role[];
}

export function bugReportDoc(
  input: ReportInput,
  reporter: Reporter,
  env: Environment,
  id: string,
  now: Date,
): Record<string, unknown> {
  const roles = rolesLabel(reporter.roles);
  return {
    id,
    title: clamp(input.title.trim(), maxTitle),
    body: clamp(input.body.trim(), maxBody),
    reporterUid: clamp(reporter.uid, 128),
    reporterName: clamp(reporter.name || "Unknown", 128),
    ...(roles !== "" ? { roles: clamp(roles, 128) } : {}),
    kind: input.kind,
    ...(input.area !== "" ? { area: clamp(input.area, 64) } : {}),
    ...(input.kind === "bug" && input.impact !== ""
      ? { impact: clamp(input.impact, 64) }
      : {}),
    ...(input.screenshotKeys && input.screenshotKeys.length > 0
      ? { screenshotKeys: input.screenshotKeys.slice(0, maxScreenshots) }
      : {}),
    appVersion: env.appVersion,
    platform: env.platform,
    osVersion: env.osVersion,
    deviceInfo: env.deviceInfo,
    status: "new",
    createdAt: now.toISOString(),
  };
}
