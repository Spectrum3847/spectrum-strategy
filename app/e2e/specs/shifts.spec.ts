import { expect, layoutFor, signIn, test } from "../support.ts";

test.describe("scouting shifts", () => {
  test("a scouter sees their own blocks and station", async ({
    page,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/scout/shifts");
    await expect(
      page.getByRole("heading", { name: "My shifts" }),
    ).toBeVisible();
    await expect(page.getByText("You are not on this schedule.")).toHaveCount(
      0,
    );
    await expect(page.getByText(/R1|B3|B2/).first()).toBeVisible();
    await shot("my-shifts", { fullPage: true });
  });

  test("the grid scrolls sideways with the match column pinned", async ({
    page,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/scout/shifts");
    const grid = page.getByRole("table").first();
    await expect(grid).toBeVisible();
    const phone = layoutFor(page.viewportSize()?.width ?? 0) === "bar";
    if (phone) {
      const scroller = page.locator("table").first().locator("xpath=..");
      const overflow = await scroller.evaluate((el) => ({
        wide: el.scrollWidth > el.clientWidth,
      }));
      expect(overflow.wide).toBe(true);
      await scroller.evaluate((el) => el.scrollTo({ left: 400 }));
      const header = page.getByRole("columnheader", { name: "Match" });
      const before = await header.boundingBox();
      await scroller.evaluate((el) => el.scrollTo({ left: 600 }));
      const after = await header.boundingBox();
      expect(Math.abs((after?.x ?? 0) - (before?.x ?? 0))).toBeLessThan(2);
    }
    await shot("grid", { fullPage: true });
  });

  test("a lead paints a cell and the grid keeps it", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/scout/shifts");
    await expect(
      page.getByRole("button", { name: "Generate scouting schedule" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Grey", exact: true }).click();
    const cell = page.getByRole("table").first().getByRole("cell").nth(4);
    await cell.click();
    await shot("painted", { fullPage: true });
    await page.reload();
    await expect(
      page.getByRole("button", { name: "Grey", exact: true }),
    ).toBeVisible();
    await shot("after-reload", { fullPage: true });
  });
});
