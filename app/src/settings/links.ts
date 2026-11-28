const repo = "https://github.com/Spectrum3847/spectrum-strategy";

export interface Link {
  title: string;
  detail: string;
  url: string;
}

export const creditLinks: Link[] = [
  {
    title: "Made by project516",
    detail: "project516.dev",
    url: "https://project516.dev",
  },
  {
    title: "project516 on GitHub",
    detail: "github.com/Project516",
    url: "https://github.com/Project516",
  },
  {
    title: "Spectrum 3847",
    detail: "FRC Team 3847, spectrum3847.org",
    url: "https://www.spectrum3847.org/",
  },
];

export const sourceLinks: Link[] = [
  {
    title: "View source on GitHub",
    detail: "github.com/Spectrum3847/spectrum-strategy",
    url: repo,
  },
  {
    title: "Run it for your own team",
    detail: "Self-hosting guide",
    url: `${repo}/blob/HEAD/docs/self-hosting.md`,
  },
  {
    title: "Contribute",
    detail: "Contributing guide",
    url: `${repo}/blob/HEAD/CONTRIBUTING.md`,
  },
];
