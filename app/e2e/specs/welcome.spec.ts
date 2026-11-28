import { expect, signIn, test } from "../support.ts";

test.describe("first visit", () => {
  test("the welcome tour shows once and can be replayed", async ({
    page,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111, firstVisit: true });
    const tour = page.getByRole("dialog");
    await expect(tour).toBeVisible();
    await shot("tour-first-step");
    await tour.getByRole("button", { name: "Next" }).click();
    await expect(page.getByTestId("tour-ring")).toBeVisible();
    await shot("tour-second-step");
    await tour.getByRole("button", { name: "Next" }).click();
    await tour.getByRole("button", { name: "Next" }).click();
    await expect(tour).toHaveAccessibleName("Scout");
    await expect(page).toHaveURL(/\/scout$/);
    await expect(page.getByTestId("tour-ring")).toBeVisible();
    await shot("tour-scout-step");
    await page.keyboard.press("Escape");
    await expect(tour).toHaveCount(0);
    await expect(page).toHaveURL(/\/$/);

    await page.reload();
    await expect(page.getByRole("navigation", { name: "Main" })).toBeVisible();
    await expect(page.getByRole("dialog")).toHaveCount(0);

    await page.goto("/settings?s=help");
    await page.getByRole("button", { name: "Show the tour" }).click();
    await expect(page.getByRole("dialog")).toBeVisible();
    await page.getByRole("button", { name: "Next" }).click();
    await page.getByRole("button", { name: "Next" }).click();
    await expect(page).toHaveURL(/\/$/);
    await page.keyboard.press("Escape");
    await expect(page).toHaveURL(/\/settings\?s=help$/);
  });

  test("the install banner shows only in an iPad or iPhone browser tab", async ({
    page,
    shot,
  }, info) => {
    await signIn(page, "scout-a", { team: 1111, firstVisit: true });
    await page.keyboard.press("Escape");
    const banner = page.getByRole("region", {
      name: "Add this app to your Home Screen",
    });
    if (info.project.name === "ipad" || info.project.name === "iphone") {
      await expect(banner).toBeVisible();
      await shot("install-banner", { fullPage: true });
      await banner.getByRole("button", { name: "Not now" }).click();
      await expect(banner).toHaveCount(0);
      await page.reload();
      await expect(
        page.getByRole("navigation", { name: "Main" }),
      ).toBeVisible();
      await expect(banner).toHaveCount(0);
    } else {
      await expect(banner).toHaveCount(0);
    }
  });
});
