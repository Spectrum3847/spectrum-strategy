import { type KeyboardEvent, type ReactNode, useEffect, useRef } from "react";
import { NavLink } from "react-router";

export interface SheetTab {
  to: string;
  label: string;
  end?: boolean;
  icon: ReactNode;
  badge?: ReactNode;
}

const focusable = "a[href], button:not([disabled])";

export function MoreSheet({
  tabs,
  action,
  onClose,
}: {
  tabs: SheetTab[];
  action?: { label: string; icon: ReactNode; onClick(): void };
  onClose(): void;
}) {
  const sheet = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    sheet.current?.querySelector<HTMLElement>(".sheet-link")?.focus();
    return () => opener?.focus();
  }, []);

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (e.key === "Escape") {
      e.stopPropagation();
      onClose();
      return;
    }
    if (e.key !== "Tab") return;
    const items = [
      ...(sheet.current?.querySelectorAll<HTMLElement>(focusable) ?? []),
    ];
    const first = items[0];
    const last = items[items.length - 1];
    if (!first || !last) return;
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    <div className="sheet-scrim">
      <button
        type="button"
        className="sheet-backdrop"
        tabIndex={-1}
        aria-hidden="true"
        onClick={onClose}
      />
      <div
        ref={sheet}
        className="sheet"
        role="dialog"
        aria-modal="true"
        aria-label="More"
        onKeyDown={onKeyDown}
      >
        <div className="sheet-head">
          <h2>More</h2>
          <button
            type="button"
            className="sheet-close"
            aria-label="Close"
            onClick={onClose}
          >
            <svg
              viewBox="0 0 24 24"
              width="24"
              height="24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              aria-hidden="true"
              focusable="false"
            >
              <path d="M6 6l12 12M18 6L6 18" />
            </svg>
          </button>
        </div>
        {action && (
          <button
            type="button"
            className="sheet-link sheet-action"
            aria-haspopup="dialog"
            onClick={() => {
              onClose();
              action.onClick();
            }}
          >
            {action.icon}
            <span className="nav-label">{action.label}</span>
          </button>
        )}
        <ul className="sheet-list">
          {tabs.map((tab) => (
            <li key={tab.to}>
              <NavLink
                to={tab.to}
                end={tab.end ?? false}
                className="sheet-link"
                onClick={onClose}
              >
                {tab.icon}
                <span className="nav-label">{tab.label}</span>
                {tab.badge}
              </NavLink>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
