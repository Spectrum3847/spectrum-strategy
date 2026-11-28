import { expect, layoutFor, navLink, signIn, test } from "../support.ts";

test.describe("navigation", () => {
  test("the bar, rail or sidebar fits the width", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    const width = page.viewportSize()?.width ?? 0;
    const layout = layoutFor(width);
    await expect(page.locator(".shell")).toHaveAttribute("data-layout", layout);
    await shot(`layout-${layout}`);

    if (layout === "bar") {
      const links = page
        .getByRole("navigation", { name: "Main" })
        .getByRole("link");
      await expect(links).toHaveCount(4);
      await expect(page.getByRole("button", { name: "More" })).toBeVisible();
    }
  });

  test("a scouter has no More on the phone bar", async ({ page, shot }) => {
    test.skip(
      layoutFor(page.viewportSize()?.width ?? 0) !== "bar",
      "phone only",
    );
    await signIn(page, "scout-a", { team: 1111 });
    await expect(page.getByRole("button", { name: "More" })).toHaveCount(0);
    await expect(
      page.getByRole("navigation", { name: "Main" }).getByRole("link"),
    ).toHaveCount(4);
    await shot("scouter-bar");
  });

  test("More opens a sheet that closes three ways", async ({ page, shot }) => {
    test.skip(
      layoutFor(page.viewportSize()?.width ?? 0) !== "bar",
      "phone only",
    );
    await signIn(page, "admin-c", { team: 1111 });
    const more = page.getByRole("button", { name: "More" });
    const sheet = page.getByRole("dialog", { name: "More" });

    await more.click();
    await expect(sheet).toBeVisible();
    for (const name of ["Picks", "Users", "Settings"]) {
      await expect(sheet.getByRole("link", { name })).toBeVisible();
    }
    await shot("more-open");

    await sheet.getByRole("button", { name: "Close" }).click();
    await expect(sheet).toBeHidden();

    await more.click();
    await page.keyboard.press("Escape");
    await expect(sheet).toBeHidden();

    await more.click();
    await page.mouse.click(10, 60);
    await expect(sheet).toBeHidden();

    await more.click();
    await sheet.getByRole("link", { name: "Picks" }).click();
    await expect(page).toHaveURL(/\/picks$/);
    await expect(more).toHaveAttribute("aria-current", "page");
    await shot("more-tab-open");
  });

  test("the sidebar collapses and expands again", async ({ page, shot }) => {
    const size = page.viewportSize();
    if (size && layoutFor(size.width) === "rail" && size.height < size.width) {
      test.skip();
    }
    if (size && layoutFor(size.width) === "rail") {
      await page.setViewportSize({ width: size.height, height: size.width });
    }
    test.skip(
      layoutFor(page.viewportSize()?.width ?? 0) !== "sidebar",
      "needs 1024px",
    );
    await signIn(page, "lead-b", { team: 1111 });
    const shell = page.locator(".shell");
    await expect(shell).toHaveAttribute("data-layout", "sidebar");
    await shot("sidebar-open");

    await page.getByRole("button", { name: "Collapse navigation" }).click();
    await expect(shell).toHaveAttribute("data-layout", "rail");
    const expand = page.getByRole("button", { name: "Expand navigation" });
    await expect(expand).toBeVisible();
    await shot("sidebar-collapsed");

    await page.reload();
    await expect(shell).toHaveAttribute("data-layout", "rail");
    await expand.click();
    await expect(shell).toHaveAttribute("data-layout", "sidebar");
    await expect(navLink(page, "Teams")).toBeVisible();
    await shot("sidebar-expanded-again");
  });

  test("portrait iPad uses the rail", async ({ page, shot }) => {
    const size = page.viewportSize();
    test.skip(
      !size || layoutFor(size.width) !== "rail",
      "tablet portrait only",
    );
    await signIn(page, "lead-b", { team: 1111 });
    await expect(page.getByRole("button", { name: /navigation/ })).toHaveCount(
      0,
    );
    await shot("rail");
  });
});
