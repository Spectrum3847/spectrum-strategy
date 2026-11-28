import {
  canOpenPath,
  isLead,
  isMentor,
  type Role,
  readsLeadPages,
} from "../auth/roles";

export interface TourStep {
  title: string;
  body: string;
  to: string | null;
  nav: string | null;
}

type Layout = "bar" | "rail" | "sidebar";

const navigation: Record<Layout, string> = {
  bar: "The bar at the bottom opens your screens. If they do not all fit, More opens the rest.",
  rail: "The bar on the left opens your screens. Your role decides which ones you see.",
  sidebar:
    "The sidebar on the left opens your screens. The menu button at its top makes it narrower.",
};

export function tourSteps(roles: Role[], layout: Layout): TourStep[] {
  const scouts = isLead(roles) || roles.includes("scouter");
  const reads = readsLeadPages(roles);
  const steps: TourStep[] = [
    {
      title: "Welcome to Spectrum Strategy",
      body: "Scouting, match plans and team analysis in one app. Pick your event first: Settings, Event. It loads the team list and the match schedule.",
      to: null,
      nav: null,
    },
    {
      title: "Finding your way",
      body: navigation[layout],
      to: null,
      nav: "nav",
    },
    {
      title: "Now",
      body: "Your next match, your next scouting shift and anything that needs attention.",
      to: "/",
      nav: "/",
    },
  ];
  if (scouts) {
    steps.push({
      title: "Scout",
      body: "Record what each robot does, match by match. An entry saves on this device first, then sends when you are online. A number on Scout counts entries not sent yet. QR codes move entries when there is no signal.",
      to: "/scout",
      nav: "/scout",
    });
  }
  steps.push({
    title: "Schedule",
    body: "Every match at your event. Search a team number to see only its matches.",
    to: "/schedule",
    nav: "/schedule",
  });
  if (reads) {
    steps.push({
      title: "Teams and matches",
      body:
        isMentor(roles) && !isLead(roles)
          ? "Teams ranks the event. Tap a team number to open that team. Open a match to read its brief in large type."
          : "Teams ranks the event. Tap a team number to open that team. Open a match for its prediction, the strategy board on the Plan tab and the brief.",
      to: "/teams",
      nav: "/teams",
    });
    steps.push({
      title: "Picks",
      body: "Rank teams for alliance selection and run the draft board live.",
      to: "/picks",
      nav: "/picks",
    });
  }
  if (roles.includes("admin")) {
    steps.push({
      title: "Users",
      body: "Set roles for new teammates. A new account has no access until you grant a role here.",
      to: "/users",
      nav: "/users",
    });
  }
  steps.push({
    title: "Settings",
    body: "Your event, team number and theme. To see this tour again, open Settings, then Help and about.",
    to: "/settings",
    nav: "/settings",
  });
  return steps.filter((s) => s.to === null || canOpenPath(roles, s.to));
}

const seenKey = "ss.tour.seen";

export function tourSeen(): boolean {
  try {
    return localStorage.getItem(seenKey) === "1";
  } catch {
    return false;
  }
}

export function markTourSeen() {
  try {
    localStorage.setItem(seenKey, "1");
  } catch {
  }
}
