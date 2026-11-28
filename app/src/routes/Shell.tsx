import { type ReactNode, useEffect, useState } from "react";
import { NavLink, Outlet, useLocation, useMatches } from "react-router";
import {
  canOpenPath,
  hasAppAccess,
  needsAdmin,
  needsDeveloper,
  type Role,
} from "../auth/roles";
import { RolesProvider, useRoles } from "../auth/rolesContext";
import { FreshnessPill } from "../freshness/FreshnessPill";
import { InstallBanner } from "../install/InstallBanner";
import { JumpDialog } from "../jump/JumpDialog";
import { useJump } from "../jump/useJump";
import { useOutbox } from "../outbox/useOutbox";
import { usePlaceWaitingPhotos } from "../photos/usePlaceWaitingPhotos";
import { UpdatePrompt } from "../pwa/UpdatePrompt";
import { ScoutDataProvider } from "../scout/ScoutData";
import { markTourSeen, tourSeen, tourSteps } from "../tour/steps";
import { Tour } from "../tour/Tour";
import { TourContext } from "../tour/tourContext";
import { TrainingBanner } from "../training/TrainingBanner";
import {
  LoadingScreen,
  NoAccessScreen,
  NotAvailable,
  RolesUnavailableScreen,
  SignedOutScreen,
} from "../ui/AccessScreens";
import { MoreSheet, type SheetTab } from "../ui/MoreSheet";
import { UnsentBanner } from "../ui/UnsentBanner";
import { unsentCounts, unsentTotal } from "../ui/unsent";
import { useUsageTracking } from "../usage/track";

export type NavLayout = "bar" | "rail" | "sidebar";

export function layoutFor(width: number): NavLayout {
  if (width < 600) return "bar";
  return width < 1024 ? "rail" : "sidebar";
}

function useLayout(): NavLayout {
  const [layout, setLayout] = useState(() => layoutFor(window.innerWidth));
  useEffect(() => {
    const onResize = () => setLayout(layoutFor(window.innerWidth));
    onResize();
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);
  return layout;
}

const collapsedKey = "ss.nav.collapsed";

function readCollapsed(): boolean {
  try {
    return localStorage.getItem(collapsedKey) === "1";
  } catch {
    return false;
  }
}

function Icon({ children }: { children: ReactNode }) {
  return (
    <svg
      className="nav-icon"
      viewBox="0 0 24 24"
      width="24"
      height="24"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

const searchIcon = (
  <Icon>
    <circle cx="11" cy="11" r="6" />
    <path d="M20 20l-4.5-4.5" />
  </Icon>
);

interface Tab extends SheetTab {
  primary?: boolean;
}

const tabs: Tab[] = [
  {
    to: "/",
    label: "Now",
    end: true,
    primary: true,
    icon: (
      <Icon>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 2" />
      </Icon>
    ),
  },
  {
    to: "/scout",
    label: "Scout",
    primary: true,
    icon: (
      <Icon>
        <rect x="5" y="4" width="14" height="17" rx="2" />
        <path d="M9 4h6v3H9zM9 14l2 2 4-4" />
      </Icon>
    ),
  },
  {
    to: "/teams",
    label: "Teams",
    primary: true,
    icon: (
      <Icon>
        <path d="M4 6h3M10 6h10M4 12h3M10 12h10M4 18h3M10 18h10" />
      </Icon>
    ),
  },
  {
    to: "/schedule",
    label: "Schedule",
    primary: true,
    icon: (
      <Icon>
        <rect x="4" y="5" width="16" height="15" rx="2" />
        <path d="M4 10h16M9 3v4M15 3v4" />
      </Icon>
    ),
  },
  {
    to: "/picks",
    label: "Picks",
    icon: (
      <Icon>
        <path d="M5 5h4v14H5zM10 5h4v9h-4zM15 5h4v5h-4z" />
      </Icon>
    ),
  },
  {
    to: "/database",
    label: "Database",
    icon: (
      <Icon>
        <ellipse cx="12" cy="6" rx="7" ry="3" />
        <path d="M5 6v12c0 1.7 3.1 3 7 3s7-1.3 7-3V6M5 12c0 1.7 3.1 3 7 3s7-1.3 7-3" />
      </Icon>
    ),
  },
  {
    to: "/ai",
    label: "AI",
    icon: (
      <Icon>
        <path d="M5 5h14v10H10l-5 4zM9 9h6M9 12h4" />
      </Icon>
    ),
  },
  {
    to: "/users",
    label: "Users",
    icon: (
      <Icon>
        <circle cx="9" cy="8" r="3" />
        <path d="M3 19c0-3 2.7-5 6-5s6 2 6 5M16 5.5a3 3 0 0 1 0 5.5M18 14.3c1.8.6 3 2.2 3 4.7" />
      </Icon>
    ),
  },
  {
    to: "/usage",
    label: "Usage",
    icon: (
      <Icon>
        <path d="M5 20V10M12 20V4M19 20v-7" />
      </Icon>
    ),
  },
  {
    to: "/settings",
    label: "Settings",
    icon: (
      <Icon>
        <path d="M4 7h10M18 7h2M4 17h2M10 17h10" />
        <circle cx="16" cy="7" r="2" />
        <circle cx="8" cy="17" r="2" />
      </Icon>
    ),
  },
];

const barLimit = 4;

export function splitTabs<T extends { primary?: boolean }>(
  visible: T[],
): { bar: T[]; more: T[] } {
  if (visible.length <= barLimit) return { bar: visible, more: [] };
  const bar = visible.filter((t) => t.primary).slice(0, barLimit);
  return { bar, more: visible.filter((t) => !bar.includes(t)) };
}

const onTab = (pathname: string, tab: SheetTab) =>
  tab.to === "/"
    ? pathname === "/"
    : pathname === tab.to || pathname.startsWith(`${tab.to}/`);

function UnsentBadge({ count }: { count: number }) {
  return (
    <>
      <span className="nav-badge" aria-hidden="true">
        {count}
      </span>
      <span className="sr-only">
        {count === 1 ? "1 entry not sent" : `${count} entries not sent`}
      </span>
    </>
  );
}

const isOpen = (handle: unknown) =>
  (handle as { open?: boolean } | undefined)?.open === true;

function Page() {
  const roles = useRoles();
  const { pathname } = useLocation();
  const matches = useMatches();
  const open = matches.some((m) => isOpen(m.handle));
  const allowed =
    open || (roles.status === "ready" && canOpenPath(roles.roles, pathname));
  return (
    <main className="page">
      <FreshnessPill />
      <InstallBanner />
      {!pathname.startsWith("/scout") && <UnsentBanner />}
      {allowed ? (
        <Outlet />
      ) : (
        <NotAvailable
          {...(needsAdmin(pathname)
            ? { who: "admin accounts" }
            : needsDeveloper(pathname)
              ? { who: "developer accounts" }
              : {})}
        />
      )}
    </main>
  );
}

function MemberShell({ roles }: { roles: Role[] }) {
  usePlaceWaitingPhotos();
  useUsageTracking();
  const layout = useLayout();
  const [collapsed, setCollapsed] = useState(readCollapsed);
  const shown: NavLayout = layout === "sidebar" && collapsed ? "rail" : layout;
  const unsent = unsentTotal(unsentCounts(useOutbox()));
  const visible = tabs.filter((tab) => canOpenPath(roles, tab.to));
  const { pathname } = useLocation();
  const [moreOpen, setMoreOpen] = useState(false);
  const jump = useJump(roles);
  const [touring, setTouring] = useState(() => !tourSeen());
  const closeTour = () => {
    markTourSeen();
    setTouring(false);
  };
  const { bar, more } =
    layout === "bar" ? splitTabs(visible) : { bar: visible, more: [] as Tab[] };
  const current = more.find((tab) => onTab(pathname, tab));
  const scoutBadge = (tab: Tab) =>
    tab.to === "/scout" && unsent > 0 ? <UnsentBadge count={unsent} /> : null;

  useEffect(() => {
    if (layout !== "bar") setMoreOpen(false);
  }, [layout]);

  const toggle = () => {
    setCollapsed((c) => {
      try {
        localStorage.setItem(collapsedKey, c ? "0" : "1");
      } catch {
      }
      return !c;
    });
  };

  return (
    <ScoutDataProvider>
      <TourContext.Provider value={{ open: () => setTouring(true) }}>
        <TrainingBanner />
        <div className="shell" data-layout={shown}>
          <nav className="nav" aria-label="Main" data-tour-tab="nav">
            {layout === "sidebar" && (
              <button
                type="button"
                className="nav-toggle"
                aria-label={
                  collapsed ? "Expand navigation" : "Collapse navigation"
                }
                aria-expanded={!collapsed}
                onClick={toggle}
              >
                <Icon>
                  <path d="M4 6h16M4 12h16M4 18h16" />
                </Icon>
                {!collapsed && <span>Spectrum Strategy</span>}
              </button>
            )}
            {jump.allowed && layout !== "bar" && (
              <button
                type="button"
                className="nav-link"
                aria-haspopup="dialog"
                aria-keyshortcuts="/"
                onClick={jump.show}
              >
                {searchIcon}
                <span className="nav-label">Find</span>
              </button>
            )}
            {bar.map((tab) => (
              <NavLink
                key={tab.to}
                to={tab.to}
                end={tab.end ?? false}
                className="nav-link"
                data-tour-tab={tab.to}
              >
                {tab.icon}
                <span className="nav-label">{tab.label}</span>
                {scoutBadge(tab)}
              </NavLink>
            ))}
            {more.length > 0 && (
              <button
                type="button"
                className="nav-link"
                data-tour-tab="more"
                aria-haspopup="dialog"
                aria-expanded={moreOpen}
                aria-current={current ? "page" : undefined}
                onClick={() => setMoreOpen(true)}
              >
                <Icon>
                  <circle cx="6" cy="12" r="1.5" />
                  <circle cx="12" cy="12" r="1.5" />
                  <circle cx="18" cy="12" r="1.5" />
                </Icon>
                <span className="nav-label">More</span>
                {current && (
                  <span className="sr-only">, {current.label} is open</span>
                )}
                {more.some((tab) => tab.to === "/scout") && unsent > 0 && (
                  <UnsentBadge count={unsent} />
                )}
              </button>
            )}
          </nav>
          {moreOpen && more.length > 0 && (
            <MoreSheet
              tabs={more.map((tab) => ({ ...tab, badge: scoutBadge(tab) }))}
              {...(jump.allowed
                ? {
                    action: {
                      label: "Find a team or match",
                      icon: searchIcon,
                      onClick: jump.show,
                    },
                  }
                : {})}
              onClose={() => setMoreOpen(false)}
            />
          )}
          <Page />
          {jump.open && <JumpDialog onClose={jump.hide} />}
          <UpdatePrompt />
          {touring && (
            <Tour
              steps={tourSteps(roles, layout)}
              layout={layout}
              barPaths={bar.map((tab) => tab.to)}
              onClose={closeTour}
            />
          )}
        </div>
      </TourContext.Provider>
    </ScoutDataProvider>
  );
}

function Gate() {
  const roles = useRoles();
  switch (roles.status) {
    case "loading":
      return <LoadingScreen />;
    case "signed-out":
      return <SignedOutScreen />;
    case "unavailable":
      return <RolesUnavailableScreen />;
    case "ready":
      return hasAppAccess(roles.roles) ? (
        <MemberShell roles={roles.roles} />
      ) : (
        <NoAccessScreen />
      );
  }
}

export function Shell() {
  return (
    <RolesProvider>
      <Gate />
    </RolesProvider>
  );
}
