import { expect, type Page } from "./support.ts";

const stepTab = (page: Page, name: string) =>
  page.getByRole("navigation", { name: "Steps" }).getByRole("button", { name });

export async function fillMatch(
  page: Page,
  shot?: (name: string) => Promise<void>,
) {
  await page.getByLabel("Scouter Name").fill("ScoutA");
  await shot?.("prematch");
  await stepTab(page, "Autonomous").click();
  await page.getByRole("button", { name: "Center Hub" }).click();
  await page
    .getByRole("button", { name: "Fuel Scored plus 5", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Fuel Scored plus 1", exact: true })
    .click();
  await shot?.("autonomous");
  await stepTab(page, "Teleop").click();
  await page
    .getByRole("button", { name: "Fuel Scored plus 10", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Fuel Scored plus 10", exact: true })
    .click();
  await page
    .getByRole("group", { name: "Defense" })
    .getByRole("button", { name: "Yes" })
    .click();
  await shot?.("teleop");
  await stepTab(page, "Endgame").click();
  await shot?.("endgame");
  await stepTab(page, "Postmatch").click();
  await page.getByLabel("Comments").fill("Generic test comment.");
  await stepTab(page, "Review").click();
  await shot?.("review");
}

export async function save(page: Page) {
  const saved = page.getByRole("heading", { name: /^Team \d+ saved$/ });
  for (let i = 0; i < 3 && !(await saved.isVisible()); i++) {
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await page.waitForTimeout(400);
  }
  await expect(saved).toBeVisible();
}
