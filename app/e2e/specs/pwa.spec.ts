import { fillMatch, save } from "../scout-flow.ts";
import { expect, navLink, signIn, test } from "../support.ts";

test.describe("offline start", () => {
  test.skip(
    ({ browserName }) => browserName !== "chromium",
    "needs the service worker",
  );

  test("an unsent entry survives closing the app offline and then sends", async ({
    page,
    context,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await navLink(page, "Scout").click();
    await expect(page.getByLabel("Team Number")).toHaveValue(/^[1-9]\d+$/);
    const controlled = () =>
      page.evaluate(() => !!navigator.serviceWorker.controller);
    for (let i = 0; i < 10 && !(await controlled()); i++) {
      await page.waitForTimeout(2000);
      await page.reload();
    }
    expect(await controlled()).toBe(true);

    await context.setOffline(true);
    await fillMatch(page);
    await save(page);
    await expect(page.getByText("On this device").first()).toBeVisible();
    await shot("saved-offline");

    await page.reload();
    await expect(page.getByLabel("Scouter Name")).toBeVisible({
      timeout: 30_000,
    });
    await expect(page.getByText(/entr(y|ies) not sent/).first()).toBeAttached();
    await shot("reopened-offline");

    await context.setOffline(false);
    await expect(page.getByText(/entr(y|ies) not sent/)).toHaveCount(0, {
      timeout: 60_000,
    });
    await shot("sent-after-reconnect");
  });
});
