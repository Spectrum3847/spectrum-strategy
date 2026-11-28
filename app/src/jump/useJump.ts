import { useCallback, useEffect, useState } from "react";
import { canOpenMatchPage, canOpenTeamPage, type Role } from "../auth/roles";

export const canJump = (roles: Role[]) =>
  canOpenTeamPage(roles) || canOpenMatchPage(roles);

const typing = (el: EventTarget | null) =>
  el instanceof HTMLElement &&
  (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName));

export function useJump(roles: Role[]) {
  const allowed = canJump(roles);
  const [open, setOpen] = useState(false);
  const show = useCallback(() => setOpen(true), []);
  const hide = useCallback(() => setOpen(false), []);

  useEffect(() => {
    if (!allowed) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || document.querySelector('[aria-modal="true"]')) {
        return;
      }
      const slash =
        e.key === "/" &&
        !e.ctrlKey &&
        !e.metaKey &&
        !e.altKey &&
        !typing(e.target);
      const palette = e.key.toLowerCase() === "k" && (e.ctrlKey || e.metaKey);
      if (!slash && !palette) return;
      e.preventDefault();
      setOpen(true);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [allowed]);

  return { allowed, open: open && allowed, show, hide };
}
