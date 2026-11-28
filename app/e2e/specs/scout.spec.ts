import { fillMatch, save } from "../scout-flow.ts";
import { expect, navLink, signIn, signOut, test } from "../support.ts";

test.describe("match scouting", () => {
  test("a full match saves and reaches the database", async ({
    page,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await navLink(page, "Scout").click();
    await expect(page.getByText(/^Match \d+$/)).toBeVisible();
    await fillMatch(page, shot);
    await save(page);
    await shot("saved");
    await expect(page.getByText("In the database").first()).toBeVisible({
      timeout: 30_000,
    });
    await shot("in-the-database");
  });

  test("an offline save waits, then sends by itself", async ({
    page,
    context,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await navLink(page, "Scout").click();
    await expect(page.getByText(/^Match \d+$/)).toBeVisible();
    await expect(page.getByLabel("Team Number")).toHaveValue(/^[1-9]\d+$/);
    await context.setOffline(true);
    await fillMatch(page);
    await save(page);
    await expect(page.getByText("On this device").first()).toBeVisible();
    await shot("saved-offline");
    await context.setOffline(false);
    await expect(page.getByText("In the database").first()).toBeVisible({
      timeout: 45_000,
    });
    await shot("sent-after-reconnect");
  });

  test("a saved entry shows its QR code", async ({ page, shot }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await navLink(page, "Scout").click();
    await expect(page.getByText(/^Match \d+$/)).toBeVisible();
    await fillMatch(page);
    await save(page);
    await page.getByRole("button", { name: "Show QR" }).first().click();
    const sheet = page.getByRole("dialog", { name: "QR code" });
    await expect(sheet).toBeVisible();
    await expect(sheet.getByRole("img").first()).toBeVisible();
    await shot("qr");
  });
});

test.describe("station iPad", () => {
  test("a lead locks the station and a scout is credited", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/settings?s=device");
    const panel = page.getByRole("region", { name: "This iPad's station" });
    await panel.getByRole("button", { name: "R1" }).click();
    await expect(panel.getByRole("button", { name: "R1" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await shot("locked", { fullPage: true });
    await signOut(page);

    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/settings?s=device");
    for (const name of ["R2", "B3"]) {
      await expect(panel.getByRole("button", { name })).toBeDisabled();
    }
    await shot("scout-sees-lock", { fullPage: true });

    await navLink(page, "Scout").click();
    await expect(page.getByText("Scouting as")).toBeVisible();
    const label = (await page.getByText(/^Match \d+$/).textContent()) ?? "";
    const block = Math.floor((Number(label.replace("Match ", "")) - 1) / 3);
    const credited = `Scout ${"ABCDEFGH"[block % 8]}`;
    await expect(page.getByText(credited).first()).toBeVisible();
    await shot("credited");

    await page.getByRole("button", { name: "Not me? Switch" }).click();
    await shot("switch");
  });
});
