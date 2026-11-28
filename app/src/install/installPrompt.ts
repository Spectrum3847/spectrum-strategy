export const dismissDays = 14;
const dismissedKey = "ss.install.dismissed";
const day = 24 * 60 * 60 * 1000;

export interface Device {
  userAgent: string;
  platform: string;
  maxTouchPoints: number;
  standalone: boolean;
}

export function isIos(
  d: Pick<Device, "userAgent" | "platform" | "maxTouchPoints">,
) {
  return (
    /iPad|iPhone|iPod/.test(d.userAgent) ||
    (d.platform === "MacIntel" && d.maxTouchPoints > 1)
  );
}

export function showInstallPrompt(
  d: Device,
  dismissedAt: number | null,
  now: number,
): boolean {
  if (!isIos(d) || d.standalone) return false;
  return dismissedAt === null || now - dismissedAt >= dismissDays * day;
}

export function readDismissed(): number | null {
  try {
    const n = Number(localStorage.getItem(dismissedKey));
    return Number.isFinite(n) && n > 0 ? n : null;
  } catch {
    return null;
  }
}

export function writeDismissed(now: number) {
  try {
    localStorage.setItem(dismissedKey, String(now));
  } catch {
  }
}

export function currentDevice(): Device {
  return {
    userAgent: navigator.userAgent,
    platform: navigator.platform,
    maxTouchPoints: navigator.maxTouchPoints,
    standalone:
      (navigator as { standalone?: boolean }).standalone === true ||
      window.matchMedia?.("(display-mode: standalone)").matches === true,
  };
}
