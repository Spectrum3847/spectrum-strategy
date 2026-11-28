import { expect, navLink, signIn, test } from "../support.ts";

const photo = {
  name: "robot.png",
  mimeType: "image/png",
  buffer: Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFElEQVR4nGP8z8Dwn4EIwESMolGF1FMIAHq1AhQ0tpSqAAAAAElFTkSuQmCC",
    "base64",
  ),
};

test.describe("pit", () => {
  test("a photo added before the form stays on the same pit entry", async ({
    page,
    net,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/scout/pit");
    await expect(page.getByText("0 of 12 done")).toBeVisible();
    await expect(
      page.getByRole("link", { name: /Team One.*Form done, no photo/ }),
    ).toBeVisible();
    await shot("todo", { fullPage: true });

    await page.getByRole("link", { name: /^Team Ten/ }).click();
    await page.locator("input[type=file][multiple]").setInputFiles(photo);
    await expect(page.locator(".photo-tile")).toHaveCount(1);
    await shot("photo-before-form", { fullPage: true });

    await page
      .getByRole("group", { name: "Drive train" })
      .getByRole("button", { name: "Swerve" })
      .click();
    await page.getByLabel("Comments").fill("Generic pit answer.");
    await shot("form-after-photo", { fullPage: true });
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByText("In the database").first()).toBeVisible({
      timeout: 30_000,
    });
    await expect.poll(() => net.photoUploads, { timeout: 30_000 }).toBe(1);

    await page.goto("/scout/pit");
    await expect(page.getByText("1 of 12 done")).toBeVisible();
    await page.getByRole("button", { name: "Done (1)" }).click();
    const team = page.getByRole("link", { name: /^Team Ten/ });
    await expect(team).toContainText("Done");
    await team.click();
    await expect(page.getByText("Editing your saved entry")).toBeVisible();
    await expect(page.getByLabel("Comments")).toHaveValue(
      "Generic pit answer.",
    );
    await expect(page.locator(".photo-tile")).toHaveCount(1);
    await shot("one-entry", { fullPage: true });
  });

  test("a photo uploads and shows as a thumbnail", async ({
    page,
    net,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/scout/pit/2020");
    await page
      .getByRole("group", { name: "Drive train" })
      .getByRole("button", { name: "Tank" })
      .click();
    await page.locator("input[type=file][multiple]").setInputFiles(photo);
    await shot("photo-added", { fullPage: true });
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect.poll(() => net.photoUploads, { timeout: 30_000 }).toBe(1);
    await shot("photo-uploaded", { fullPage: true });
  });

  test("a photo taken offline waits, then uploads", async ({
    page,
    context,
    net,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/scout/pit/3030");
    await page
      .getByRole("group", { name: "Drive train" })
      .getByRole("button", { name: "Tank" })
      .click();
    await context.setOffline(true);
    await page.locator("input[type=file][multiple]").setInputFiles(photo);
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByText("On this device").first()).toBeVisible();
    expect(net.photoUploads).toBe(0);
    await shot("photo-offline");
    await context.setOffline(false);
    await expect.poll(() => net.photoUploads, { timeout: 60_000 }).toBe(1);
    await shot("photo-after-reconnect");
  });

  test("IndexedDB keeps a photo blob (diagnostic)", async ({ page }) => {
    await signIn(page, "scout-a", { team: 1111 });
    const result = await page.evaluate(
      () =>
        new Promise<string>((resolve) => {
          const open = indexedDB.open("e2e-probe", 1);
          open.onupgradeneeded = () => open.result.createObjectStore("items");
          open.onerror = () => resolve("open failed");
          open.onsuccess = () => {
            const tx = open.result.transaction("items", "readwrite");
            tx.objectStore("items").put({ blob: new Blob(["x"]) }, "a");
            tx.oncomplete = () => resolve("stored");
            tx.onabort = () => resolve(`aborted: ${String(tx.error)}`);
          };
        }),
    );
    test
      .info()
      .annotations.push({ type: "indexeddb-blob", description: result });
    console.log(`indexeddb-blob ${test.info().project.name}: ${result}`);
  });
});

test.describe("prescout", () => {
  test("a record for a team saves", async ({ page, shot }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await navLink(page, "Scout").click();
    await page.getByRole("link", { name: "Prescout" }).click();
    await shot("list", { fullPage: true });
    await page.goto("/scout/prescout/3333");
    await expect(page.getByText("No records for this team yet.")).toBeVisible();
    await page.getByRole("link", { name: "Add record" }).click();

    await page.getByLabel("Event Name").fill("2026test");
    await page
      .getByRole("group", { name: "Match Type" })
      .getByRole("button", { name: "Qual" })
      .click();
    await page.getByLabel("Match Number").fill("7");
    await page
      .getByRole("group", { name: "Starting Position" })
      .getByRole("button", { name: "Center Hub" })
      .click();
    await page
      .getByRole("button", { name: "Auto: Fuel Scored plus 5" })
      .click();
    await page
      .getByRole("group", { name: "Auto Climb (L1)" })
      .getByRole("button", { name: "N/A" })
      .click();
    await page
      .getByRole("button", { name: "Teleop: Fuel Scored plus 10" })
      .click();
    await page
      .getByRole("group", { name: "Endgame Climb" })
      .getByRole("button", { name: "L1", exact: true })
      .click();
    await shot("form", { fullPage: true });
    await page.getByRole("button", { name: "Save", exact: true }).click();
    await expect(page.getByText("In the database").first()).toBeVisible({
      timeout: 30_000,
    });
    await shot("saved");
  });
});

test.describe("T-REx", () => {
  test("a report with a rating saves", async ({ page, shot }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/scout/trex");
    await page.getByRole("button", { name: "Defense" }).click();
    await page.getByLabel("Team number").fill("2222");
    await page.getByLabel("Match number").fill("5");
    await page.getByRole("radio", { name: "4" }).check();
    await expect(page.getByRole("radio", { name: "4" })).toBeChecked();
    await page.getByLabel("Report").fill("Generic defense report.");
    await shot("form", { fullPage: true });
    await page.getByRole("button", { name: "Save report" }).click();
    await expect(page.getByText("In the database").first()).toBeVisible({
      timeout: 30_000,
    });
    await shot("saved");

    await page.goto("/scout/trex/reports");
    await page.getByText("Team 2222", { exact: true }).click();
    await expect(page.getByText("Generic defense report.")).toBeVisible();
    await expect(page.getByText("Rating 4 of 5").first()).toBeVisible();
    await shot("reports", { fullPage: true });
  });
});
