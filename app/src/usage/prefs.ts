import { useSyncExternalStore } from "react";

const enabledKey = "ss.telemetry.enabled";
const deviceKey = "ss.telemetry.deviceId";

function readEnabled(): boolean {
  try {
    return localStorage.getItem(enabledKey) !== "0";
  } catch {
    return true;
  }
}

let value = readEnabled();
const listeners = new Set<() => void>();

export const sharingStore = {
  get: () => value,
  set(next: boolean) {
    value = next;
    try {
      localStorage.setItem(enabledKey, next ? "1" : "0");
    } catch {
    }
    for (const notify of listeners) notify();
  },
  subscribe(notify: () => void) {
    listeners.add(notify);
    return () => listeners.delete(notify);
  },
  reload() {
    value = readEnabled();
    for (const notify of listeners) notify();
  },
};

export const useSharing = () =>
  useSyncExternalStore(sharingStore.subscribe, sharingStore.get, () => true);

let memory: string | null = null;

export function deviceId(): string {
  try {
    const stored = localStorage.getItem(deviceKey);
    if (stored) return stored;
    memory ??= crypto.randomUUID();
    localStorage.setItem(deviceKey, memory);
  } catch {
    memory ??= crypto.randomUUID();
  }
  return memory;
}
