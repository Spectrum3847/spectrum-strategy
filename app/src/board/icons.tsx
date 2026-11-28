import type { ReactNode } from "react";

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg
      className="icon"
      viewBox="0 0 24 24"
      width="24"
      height="24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

export const PenIcon = () => (
  <Icon>
    <path d="M4 20l1-4L16 5l3 3L8 19z" />
    <path d="M14 7l3 3" />
  </Icon>
);

export const RobotIcon = () => (
  <Icon>
    <rect x="5" y="8" width="14" height="11" rx="2" />
    <path d="M12 4v4" />
    <path d="M9 13h.01M15 13h.01" />
  </Icon>
);

export const EraserIcon = () => (
  <Icon>
    <path d="M3 17l9-9 7 7-5 5H7z" />
    <path d="M13 20h8" />
  </Icon>
);

export const UndoIcon = () => (
  <Icon>
    <path d="M9 14L4 9l5-5" />
    <path d="M4 9h10a6 6 0 0 1 0 12h-3" />
  </Icon>
);

export const RedoIcon = () => (
  <Icon>
    <path d="M15 14l5-5-5-5" />
    <path d="M20 9H10a6 6 0 0 0 0 12h3" />
  </Icon>
);

export const ZoomInIcon = () => (
  <Icon>
    <circle cx="11" cy="11" r="7" />
    <path d="M21 21l-5-5M11 8v6M8 11h6" />
  </Icon>
);

export const ZoomOutIcon = () => (
  <Icon>
    <circle cx="11" cy="11" r="7" />
    <path d="M21 21l-5-5M8 11h6" />
  </Icon>
);

export const FitIcon = () => (
  <Icon>
    <circle cx="12" cy="12" r="4" />
    <path d="M12 3v3M12 18v3M3 12h3M18 12h3" />
  </Icon>
);

export const ExpandIcon = () => (
  <Icon>
    <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
  </Icon>
);

export const CollapseIcon = () => (
  <Icon>
    <path d="M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5" />
  </Icon>
);

export const TriangleIcon = () => (
  <Icon>
    <path d="M12 5l8 14H4z" />
  </Icon>
);

export const CircleIcon = () => (
  <Icon>
    <circle cx="12" cy="12" r="8" />
  </Icon>
);

export const SquareIcon = () => (
  <Icon>
    <rect x="5" y="5" width="14" height="14" />
  </Icon>
);

export const CheckIcon = () => (
  <Icon>
    <path d="M5 13l4 4 10-10" />
  </Icon>
);

export const TextIcon = () => (
  <Icon>
    <path d="M4 5h16M12 5v14M8 19h8" />
  </Icon>
);

export const ShareIcon = () => (
  <Icon>
    <path d="M12 15V4M8 8l4-4 4 4" />
    <path d="M5 12v7h14v-7" />
  </Icon>
);
