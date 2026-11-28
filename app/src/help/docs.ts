import type { Role } from "../auth/roles";

export interface Doc {
  id: string;
  title: string;
  detail: string;
  roles: Role[];
}

const members: Role[] = ["scouter", "strategy", "admin", "developer"];
const leads: Role[] = ["strategy", "admin", "developer"];
const admins: Role[] = ["admin", "developer"];

export const catalog: Doc[] = [
  {
    id: "using-the-app",
    title: "Using Spectrum Strategy",
    detail: "How the app works, plus answers to common questions.",
    roles: [...members, "mentor"],
  },
  {
    id: "scouter-manual",
    title: "Scouter Manual",
    detail: "How to capture scouting data and handle accuracy alerts.",
    roles: members,
  },
  {
    id: "strategy-manual",
    title: "Strategy Manual",
    detail: "The strategy board, prematch analysis and playoff ranking.",
    roles: [...leads, "mentor"],
  },
  {
    id: "admin-manual",
    title: "Admin Manual",
    detail: "User management, configuration and integrations.",
    roles: admins,
  },
  {
    id: "scouting-accuracy-mapping-guide",
    title: "Scouting accuracy: mapping guide",
    detail: "Which fields are checked and how lenient alerts are.",
    roles: leads,
  },
  {
    id: "scouting-accuracy-slack-setup",
    title: "Scouting accuracy: Slack setup",
    detail: "Turn on Slack notifications for accuracy alerts.",
    roles: admins,
  },
];

const firstFor: Partial<Record<Role, string[]>> = {
  scouter: ["scouter-manual"],
  mentor: ["strategy-manual"],
  strategy: ["strategy-manual", "scouter-manual"],
  admin: ["admin-manual", "strategy-manual", "scouter-manual"],
  developer: ["admin-manual", "strategy-manual", "scouter-manual"],
};

const loaders = import.meta.glob(
  [
    "../../../docs/using-the-app.md",
    "../../../docs/scouter-manual.md",
    "../../../docs/strategy-manual.md",
    "../../../docs/admin-manual.md",
    "../../../docs/scouting-accuracy-mapping-guide.md",
    "../../../docs/scouting-accuracy-slack-setup.md",
  ],
  { query: "?raw", import: "default" },
) as Record<string, () => Promise<string>>;

const loaderFor = (id: string) => loaders[`../../../docs/${id}.md`];

export const bundledIds = (): Set<string> =>
  new Set(catalog.map((d) => d.id).filter((id) => loaderFor(id) !== undefined));

const precedence: Role[] = [
  "admin",
  "developer",
  "strategy",
  "mentor",
  "scouter",
];

export function docsFor(roles: Role[], bundled = bundledIds()): Doc[] {
  const primary = precedence.find((r) => roles.includes(r));
  const first = (primary && firstFor[primary]) || [];
  const rank = (doc: Doc) => {
    const i = first.indexOf(doc.id);
    return i === -1 ? Number.POSITIVE_INFINITY : i;
  };
  return catalog
    .filter((d) => bundled.has(d.id) && d.roles.some((r) => roles.includes(r)))
    .map((doc, order) => ({ doc, order, rank: rank(doc) }))
    .sort((a, b) => a.rank - b.rank || a.order - b.order)
    .map((x) => x.doc);
}

export const loadDoc = (id: string): Promise<string> => {
  const load = loaderFor(id);
  return load ? load() : Promise.reject(new Error(`no doc ${id}`));
};

export type LinkTarget =
  | { kind: "internal"; to: string }
  | { kind: "external"; href: string }
  | { kind: "none" };

export function resolveLink(href: string, bundled: Set<string>): LinkTarget {
  const value = href.trim();
  if (value.startsWith("#")) return { kind: "internal", to: value };
  if (/^(https?:|mailto:)/i.test(value)) {
    return { kind: "external", href: value };
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(value) || value.startsWith("//")) {
    return { kind: "none" };
  }
  const [path = "", hash = ""] = value.split("#", 2);
  const match = /^(?:\.\/)?([a-z0-9-]+)\.md$/i.exec(path);
  const id = match?.[1];
  if (id === undefined || !bundled.has(id)) return { kind: "none" };
  return { kind: "internal", to: `/help/${id}${hash ? `#${hash}` : ""}` };
}

export function slugger(): (text: string) => string {
  const seen = new Map<string, number>();
  return (text) => {
    const base = text
      .toLowerCase()
      .replace(/[^\p{L}\p{N} _-]/gu, "")
      .trim()
      .replace(/ /g, "-");
    const n = seen.get(base) ?? 0;
    seen.set(base, n + 1);
    return n === 0 ? base : `${base}-${n}`;
  };
}
