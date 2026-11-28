import type { OutboxStatus } from "./confirm";

interface Item {
  path: string;
  status: OutboxStatus;
}

export function whenInDatabase(
  path: string,
  read: () => Item[],
  subscribe: (notify: () => void) => () => void,
): Promise<boolean> {
  return new Promise((resolve) => {
    let stop: (() => void) | null = null;
    const check = () => {
      const item = read().find((i) => i.path === path);
      const done =
        !item || item.status === "in-database" || item.status === "refused";
      if (!done) return false;
      stop?.();
      resolve(item?.status === "in-database");
      return true;
    };
    if (check()) return;
    stop = subscribe(() => void check());
  });
}
