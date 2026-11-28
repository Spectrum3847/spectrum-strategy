export const maxType = 64;
export const maxDetail = 128;

export interface Env {
  appVersion: string;
  platform: string;
  osVersion: string;
  locale: string;
}

export interface TelemetryDeps {
  enabled(): boolean;
  suppressed(): boolean;
  deviceId(): string;
  env(): Env;
  write(id: string, data: Record<string, string>): Promise<unknown>;
  now(): Date;
  newId(): string;
}

const clamp = (value: string, max: number) =>
  value.length <= max ? value : value.slice(0, max);

export function telemetryEvent(
  type: string,
  detail: string | undefined,
  id: string,
  deviceId: string,
  env: Env,
  now: Date,
): Record<string, string> {
  return {
    id,
    type: clamp(type, maxType),
    deviceId,
    appVersion: clamp(env.appVersion, 64),
    platform: clamp(env.platform, 64),
    osVersion: clamp(env.osVersion, 128),
    ...(env.locale ? { locale: clamp(env.locale, 32) } : {}),
    ...(detail ? { detail: clamp(detail, maxDetail) } : {}),
    createdAt: now.toISOString(),
  };
}

export function createTelemetry(deps: TelemetryDeps) {
  return {
    log(type: string, detail?: string): void {
      try {
        if (!deps.enabled() || deps.suppressed()) return;
        const id = deps.newId();
        const data = telemetryEvent(
          type,
          detail,
          id,
          deps.deviceId(),
          deps.env(),
          deps.now(),
        );
        deps.write(id, data).catch(() => undefined);
      } catch {
      }
    },
  };
}

const screens: [string, string][] = [
  ["/scout", "Scout"],
  ["/teams", "Prematch"],
  ["/matches", "Strategy"],
  ["/picks", "Picks"],
  ["/database", "Database"],
  ["/ai", "AI"],
  ["/schedule", "Schedule"],
  ["/help", "Docs"],
  ["/users", "Users"],
  ["/usage", "Usage"],
  ["/settings", "Settings"],
];

export function screenName(pathname: string): string | null {
  if (pathname === "/" || pathname === "") return "Now";
  const hit = screens.find(
    ([base]) => pathname === base || pathname.startsWith(`${base}/`),
  );
  return hit ? hit[1] : null;
}

export function createTracker(log: (type: string, detail?: string) => void) {
  let opened = false;
  let last = "Now";
  return {
    visit(pathname: string): void {
      if (!opened) {
        opened = true;
        log("app_open");
      }
      const name = screenName(pathname);
      if (name === null || name === last) return;
      last = name;
      log("tab_open", name);
    },
  };
}
