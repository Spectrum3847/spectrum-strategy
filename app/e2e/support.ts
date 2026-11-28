import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { test as base, expect, type Page } from "@playwright/test";
import { mockNetwork, type NetworkLog } from "./mocks.ts";

export type { Page };
export { expect };

const out = process.env.E2E_OUT ?? "out";
const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 48);

interface ShotOptions {
  fullPage?: boolean;
}
export type Shot = (name: string, options?: ShotOptions) => Promise<void>;

async function audit(page: Page) {
  return page.evaluate(() => {
    const shown = (el: Element) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      return (
        r.width > 0 &&
        r.height > 0 &&
        s.visibility !== "hidden" &&
        s.display !== "none"
      );
    };
    const label = (el: Element) =>
      (
        el.getAttribute("aria-label") ||
        el.textContent ||
        el.getAttribute("name") ||
        el.tagName
      )
        .trim()
        .replace(/\s+/g, " ")
        .slice(0, 40);
    const small = [
      ...document.querySelectorAll(
        "button, a[href], select, input:not([type=hidden]), textarea, [role=button], [role=tab]",
      ),
    ]
      .filter(shown)
      .map((el) => ({ el, r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.width < 43.5 || r.height < 43.5)
      .map(
        ({ el, r }) =>
          `${label(el)} ${Math.round(r.width)}x${Math.round(r.height)}`,
      );
    const wide = [...document.querySelectorAll("body *")]
      .filter(shown)
      .filter((el) => el.getBoundingClientRect().right > window.innerWidth + 1)
      .filter(
        (el) =>
          !el.closest(
            "[data-scroll], .grid-scroll, table, .table-wrap, .scroll-x",
          ),
      )
      .slice(0, 5)
      .map(
        (el) =>
          `${el.tagName.toLowerCase()}.${String(el.className).slice(0, 30)} ${label(el)}`,
      );
    return {
      pageScrollsSideways:
        document.documentElement.scrollWidth >
        document.documentElement.clientWidth + 1,
      small: small.slice(0, 12),
      beyondViewport: wide,
    };
  });
}

export const test = base.extend<{ net: NetworkLog; shot: Shot }>({
  net: [
    async ({ context }, use) => {
      const log = await mockNetwork(context);
      await use(log);
      expect(log.unexpected, "requests outside the mocks").toEqual([]);
    },
    { auto: true },
  ],
  shot: async ({ page }, use, testInfo) => {
    const dir = join(out, testInfo.project.name);
    mkdirSync(dir, { recursive: true });
    const spec = slug(
      testInfo.file.split("/").pop()?.replace(".spec.ts", "") ?? "spec",
    );
    let n = 0;
    await use(async (name, options = {}) => {
      n += 1;
      const file = `${spec}__${slug(testInfo.title)}__${String(n).padStart(2, "0")}-${slug(name)}.png`;
      await page.screenshot({
        path: join(dir, file),
        fullPage: options.fullPage ?? false,
      });
      const found = await audit(page).catch(() => null);
      if (found) {
        appendFileSync(
          join(dir, "audit.ndjson"),
          `${JSON.stringify({ file, ...found })}\n`,
        );
      }
    });
  },
});

export async function signIn(
  page: Page,
  uid: string,
  options: { team?: number; shell?: boolean; firstVisit?: boolean } = {},
) {
  if (!options.firstVisit) {
    await page.addInitScript(() => {
      localStorage.setItem("ss.tour.seen", "1");
      localStorage.setItem("ss.install.dismissed", String(Date.now()));
    });
  }
  if (options.team !== undefined) {
    const team = String(options.team);
    await page.addInitScript((t) => {
      if (!localStorage.getItem("ss.device.team")) {
        localStorage.setItem("ss.device.team", t);
      }
    }, team);
  }
  await page.goto("/");
  await page.getByLabel("Test account").selectOption(uid);
  await page.getByRole("button", { name: "Test sign-in" }).click();
  if (options.shell === false) return;
  await expect(page.getByRole("navigation", { name: "Main" })).toBeVisible({
    timeout: 30_000,
  });
}

export async function signOut(page: Page) {
  await page.goto("/settings?s=account");
  await page.getByRole("button", { name: /sign out/i }).click();
  await expect(page.getByLabel("Test account")).toBeVisible();
}

export const layoutFor = (width: number) =>
  width < 600 ? "bar" : width < 1024 ? "rail" : "sidebar";

export const navLink = (page: Page, name: string) =>
  page.getByRole("navigation", { name: "Main" }).getByRole("link", { name });
