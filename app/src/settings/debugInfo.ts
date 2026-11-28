import { environment } from "../reports/bugReport";

export interface DebugInput {
  build: { version: string; sha: string; time: string };
  browser: { userAgent: string; maxTouchPoints: number; standalone: boolean };
  online: boolean;
}

export function debugRows(input: DebugInput): [string, string][] {
  const env = environment(input.build, input.browser);
  return [
    ["App version", input.build.version],
    ["Commit", input.build.sha],
    ["Built", input.build.time],
    ["Platform", env.osVersion || "Unknown"],
    ["Browser", input.browser.userAgent === "" ? "Unknown" : env.deviceInfo],
    ["Connection", input.online ? "Online" : "Offline"],
  ];
}

export const debugText = (rows: [string, string][]) =>
  rows.map(([label, value]) => `${label}: ${value}`).join("\n");
