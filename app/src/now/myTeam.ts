import { useSyncExternalStore } from "react";

const key = "ss.device.team";
const maxTeam = 99999;
export const defaultTeam = 3847;

function read(): number {
  try {
    const n = Number(localStorage.getItem(key));
    return Number.isInteger(n) && n > 0 && n <= maxTeam ? n : defaultTeam;
  } catch {
    return defaultTeam;
  }
}

let value = read();
const listeners = new Set<() => void>();

export const myTeamStore = {
  get: () => value,
  set(team: number | null) {
    value = team ?? defaultTeam;
    try {
      if (team === null) localStorage.removeItem(key);
      else localStorage.setItem(key, String(team));
    } catch {
    }
    for (const notify of listeners) notify();
  },
  subscribe(notify: () => void) {
    listeners.add(notify);
    return () => listeners.delete(notify);
  },
  reload() {
    value = read();
    for (const notify of listeners) notify();
  },
};

export const useMyTeam = () =>
  useSyncExternalStore(myTeamStore.subscribe, myTeamStore.get);

export function parseTeamNumber(text: string): number | null {
  const m = /^(?:frc)?\s*(\d{1,5})$/i.exec(text.trim());
  const n = m ? Number(m[1]) : 0;
  return n > 0 && n <= maxTeam ? n : null;
}
