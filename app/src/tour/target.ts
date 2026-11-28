export type NavLayout = "bar" | "rail" | "sidebar";

export interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

export function targetKey(
  nav: string | null,
  barPaths: string[],
): string | null {
  if (nav === null) return null;
  if (nav === "nav" || barPaths.includes(nav)) return nav;
  return "more";
}

export function findTarget(root: ParentNode, key: string | null) {
  if (key === null) return null;
  return root.querySelector<HTMLElement>(`[data-tour-tab="${key}"]`);
}

const pad = 4;

export function boxOf(el: Element | null): Box | null {
  if (!el) return null;
  const r = el.getBoundingClientRect();
  if (r.width === 0 || r.height === 0) return null;
  return {
    left: r.left - pad,
    top: r.top - pad,
    width: r.width + 2 * pad,
    height: r.height + 2 * pad,
  };
}

export const sameBox = (a: Box | null, b: Box | null) =>
  a === b ||
  (a !== null &&
    b !== null &&
    a.left === b.left &&
    a.top === b.top &&
    a.width === b.width &&
    a.height === b.height);

export interface Placement {
  place: "top" | "side";
  clear: number;
}

export function placeCard(
  box: Box | null,
  layout: NavLayout,
  gap = 16,
): Placement | null {
  if (!box) return null;
  if (layout === "bar") {
    return { place: "top", clear: Math.max(box.top - 2 * gap, 160) };
  }
  return { place: "side", clear: box.left + box.width + gap };
}

export function holePath(box: Box): string {
  const { left: x, top: y, width: w, height: h } = box;
  const r = x + w;
  const b = y + h;
  return `polygon(evenodd, 0 0, 100% 0, 100% 100%, 0 100%, 0 0, ${x}px ${y}px, ${x}px ${b}px, ${r}px ${b}px, ${r}px ${y}px, ${x}px ${y}px)`;
}
