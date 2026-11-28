export const sections = [
  {
    id: "event",
    title: "Event",
    detail: "The event this device follows, and training.",
  },
  {
    id: "device",
    title: "This device",
    detail:
      "Team number, station lock, theme, shift reminders and the app cache.",
  },
  {
    id: "data",
    title: "Data",
    detail: "Unsent changes and the CSV export.",
  },
  {
    id: "forms",
    title: "Forms",
    detail: "The scout, pit and prescout forms.",
  },
  {
    id: "account",
    title: "Account",
    detail: "Sign in and sign out.",
  },
  {
    id: "help",
    title: "Help and about",
    detail: "Manuals, report a problem, version, links and licenses.",
  },
] as const;

export type Section = (typeof sections)[number];

export const sectionFor = (id: string | null): Section | null =>
  sections.find((s) => s.id === id) ?? null;
