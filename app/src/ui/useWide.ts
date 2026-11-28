import { useSyncExternalStore } from "react";

const subscribeWidth = (notify: () => void) => {
  window.addEventListener("resize", notify);
  return () => window.removeEventListener("resize", notify);
};

export const useWide = () =>
  useSyncExternalStore(
    subscribeWidth,
    () => window.innerWidth >= 600,
    () => true,
  );
