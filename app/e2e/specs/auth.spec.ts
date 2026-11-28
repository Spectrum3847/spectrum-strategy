import { expect, layoutFor, navLink, signIn, test } from "../support.ts";

test.describe("sign-in and roles", () => {
  test("the test sign-in is the only way in", async ({ page, shot }) => {
    await page.goto("/");
    await expect(
      page.getByRole("heading", { name: "You are signed out" }),
    ).toBeVisible();
    await expect(
      page.getByRole("heading", { name: "Test sign-in" }),
    ).toBeVisible();
    await shot("signed-out", { fullPage: true });
  });

  test("a scouter sees the scouting tabs only", async ({ page, shot }) => {
    await signIn(page, "scout-a", { team: 1111 });
    for (const name of ["Now", "Scout", "Schedule", "Settings"]) {
      await expect(navLink(page, name)).toBeVisible();
    }
    await expect(navLink(page, "Teams")).toHaveCount(0);
    await expect(navLink(page, "Picks")).toHaveCount(0);
    await expect(navLink(page, "Users")).toHaveCount(0);
    await shot("now");
    await page.goto("/teams");
    await expect(
      page.getByRole("heading", { name: "Not available for your role" }),
    ).toBeVisible();
    await shot("refused-teams");
  });

  test("a strategy lead sees Teams and Picks, not Users", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    const layout = layoutFor(page.viewportSize()?.width ?? 0);
    if (layout !== "bar") {
      await expect(navLink(page, "Teams")).toBeVisible();
      await expect(navLink(page, "Picks")).toBeVisible();
    }
    await expect(navLink(page, "Users")).toHaveCount(0);
    await shot("now");
  });

  test("an admin reaches Users", async ({ page, shot }) => {
    await signIn(page, "admin-c", { team: 1111 });
    await page.goto("/users");
    await expect(
      page.getByRole("heading", { name: "Users" }).first(),
    ).toBeVisible();
    await shot("users", { fullPage: true });
  });

  test("an account with no role gets the no access screen", async ({
    page,
    shot,
  }) => {
    await signIn(page, "viewer-d", { shell: false });
    await expect(
      page.getByRole("heading", { name: "No access" }),
    ).toBeVisible();
    await shot("no-access");
  });
});
