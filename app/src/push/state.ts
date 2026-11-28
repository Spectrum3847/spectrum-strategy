export type PushState =
  | "unsupported"
  | "needs-home-screen"
  | "denied"
  | "off"
  | "on";

export interface PushEnv {
  ios: boolean;
  standalone: boolean;
  hasPush: boolean;
  permission: NotificationPermission;
  subscribed: boolean;
}

export function pushState(env: PushEnv): PushState {
  if (env.ios && !env.standalone) return "needs-home-screen";
  if (!env.hasPush) return "unsupported";
  if (env.permission === "denied") return "denied";
  return env.permission === "granted" && env.subscribed ? "on" : "off";
}

export function isIos(ua: string, platform: string, touchPoints: number) {
  return (
    /iPhone|iPad|iPod/.test(ua) || (platform === "MacIntel" && touchPoints > 1)
  );
}

export function userAgentSummary(ua: string): string {
  const browser = /Edg\//.test(ua)
    ? "Edge"
    : /OPR\//.test(ua)
      ? "Opera"
      : /Firefox\/|FxiOS\//.test(ua)
        ? "Firefox"
        : /Chrome\/|CriOS\//.test(ua)
          ? "Chrome"
          : /Safari\//.test(ua)
            ? "Safari"
            : "Browser";
  const system = /iPhone/.test(ua)
    ? "iPhone"
    : /iPad/.test(ua)
      ? "iPad"
      : /Android/.test(ua)
        ? "Android"
        : /Windows/.test(ua)
          ? "Windows"
          : /Mac OS X/.test(ua)
            ? "Mac"
            : /CrOS/.test(ua)
              ? "ChromeOS"
              : /Linux/.test(ua)
                ? "Linux"
                : "unknown system";
  return `${browser} on ${system}`;
}
