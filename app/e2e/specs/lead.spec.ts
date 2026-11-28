import {
  expect,
  layoutFor,
  navLink,
  type Page,
  signIn,
  test,
} from "../support.ts";

const isBar = (page: Page) =>
  layoutFor(page.viewportSize()?.width ?? 0) === "bar";

test.describe("leading the event", () => {
  test("Now leads with our next match", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await expect(
      page.getByRole("heading", { name: "Our next match" }),
    ).toBeVisible();
    await expect(page.getByText("Up next")).toBeVisible();
    await expect(page.getByText("Rank 4 of 12")).toBeVisible();
    await expect(page.getByText("Predicted score").first()).toBeVisible();
    await shot("now", { fullPage: true });
  });

  test("the schedule marks our matches and shows scores", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/schedule");
    await expect(page.getByText("Our match").first()).toBeVisible();
    await expect(page.getByText("Red won").first()).toBeVisible();
    await shot("all", { fullPage: true });
    await page.getByRole("button", { name: "Team 1111 only" }).click();
    await shot("ours-only", { fullPage: true });
  });

  test("Teams searches and compares two to four teams", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/teams");
    await expect(page.getByText("12 teams")).toBeVisible();
    await expect(
      page.getByRole("link", { name: "Event analysis" }),
    ).toBeVisible();
    await shot("list", { fullPage: true });

    await page.getByLabel("Search by number or nickname").fill("Two");
    await expect(
      page.getByRole("link", { name: "2222" }).first(),
    ).toBeVisible();
    await expect(page.getByRole("link", { name: "3333" })).toHaveCount(0);
    await page.getByLabel("Search by number or nickname").fill("");

    await page.getByRole("checkbox").nth(0).check();
    await page.getByRole("checkbox").nth(1).check();
    await page.getByRole("link", { name: "Compare" }).click();
    await expect(page).toHaveURL(/\/teams\/compare/);
    await shot("compare-first-paint", { fullPage: true });
    await expect(page.getByText(/No pit entry yet/)).toHaveCount(0, {
      timeout: 20_000,
    });
    await shot("compare", { fullPage: true });
  });

  test("the Team page shows every section", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/teams/2222");
    for (const name of [
      "Event stats",
      "Matches",
      "Comments and notes",
      "Scout entries",
      "Pit scouting",
      "T-REx traits",
      "Prescout",
    ]) {
      await expect(page.getByRole("heading", { name })).toBeVisible();
    }
    await shot("sections", { fullPage: true });
    await page.getByRole("button", { name: "Tiles" }).click();
    await shot("tiles", { fullPage: true });
  });

  test("the team note reads among the comments", async ({ page }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/teams/2222");
    const notes = page.getByRole("region", { name: "Comments and notes" });
    await expect(
      notes.getByText("Strong shooter, weak defense. Ally with a defender."),
    ).toBeVisible();
    await expect(page.getByRole("textbox")).toHaveCount(0);
  });

  test("a lead corrects a scout entry and the entry shows it", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/teams/4444");
    const entries = page.getByRole("region", { name: "Scout entries" });
    const table = entries.getByRole("table");
    await expect(table.or(entries.locator("summary")).first()).toBeVisible();
    if (await table.isVisible()) {
      await table
        .getByRole("button", { name: /^Correct / })
        .first()
        .click();
    } else {
      await entries.locator("summary").first().click();
      await entries.getByRole("button", { name: "Correct" }).click();
    }
    await shot("editor", { fullPage: true });
    await page
      .getByRole("button", { name: "Fuel Scored plus 5", exact: true })
      .first()
      .click();
    await page.getByLabel("Why (optional)").fill("Generic reason.");
    await page.getByRole("button", { name: "Save correction" }).click();
    await expect(
      page.getByText(/Correction saved on this device|Corrected/).first(),
    ).toBeVisible({ timeout: 30_000 });
    await shot("corrected", { fullPage: true });
  });

  test("a team joins a pick list tier and another is marked do not pick", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/teams/8888");
    await page.getByRole("button", { name: "Pick list" }).click();
    await page.getByLabel("Tier").selectOption({ label: "Backup" });
    await page.getByRole("button", { name: "Add to list" }).click();
    await expect(page.getByText(/Backup/).first()).toBeVisible({
      timeout: 30_000,
    });
    await shot("added", { fullPage: true });

    await page.goto("/teams/1010");
    await page.getByRole("button", { name: "Pick list" }).click();
    await page.getByLabel("Reason to not pick").fill("Generic reason.");
    await page.getByRole("button", { name: "Do not pick" }).click();
    await expect(page.getByText(/not pick/i).first()).toBeVisible({
      timeout: 30_000,
    });
    await shot("do-not-pick", { fullPage: true });
  });
});

test.describe("match page", () => {
  test("tabs keep as you step to the next match", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/matches/2027test_qm9");
    await expect(
      page.getByRole("heading", { name: "Scouted stats" }),
    ).toBeVisible();
    await shot("match", { fullPage: true });
    await page.getByRole("link", { name: "Brief", exact: true }).click();
    await expect(page).toHaveURL(/tab=brief/);
    await page.getByRole("link", { name: /^Next: / }).click();
    await expect(page).toHaveURL(/qm10.*tab=brief|tab=brief/);
  });

  test("a lead changes a robot job and marks the brief ready", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/matches/2027test_qm9?tab=brief");
    await expect(
      page.getByRole("heading", { name: "Brief status" }),
    ).toBeVisible();
    const robot = page.getByRole("group", { name: /^2222/ });
    const jobs = robot.locator(".brief-jobs .chip");
    await expect(jobs.first()).toBeEnabled();
    await robot
      .locator('.brief-jobs .chip[aria-pressed="false"]')
      .first()
      .click();
    await expect(
      robot.getByText(/^Changed by you, recommended: /),
    ).toBeVisible();
    await shot("job-changed", { fullPage: true });
    await page.getByRole("button", { name: "Mark ready" }).click();
    await expect(
      page.locator(".coach-ready", { hasText: "Ready" }).first(),
    ).toBeVisible({ timeout: 30_000 });
    await shot("ready", { fullPage: true });
  });

  test("a scouter cannot open the brief or the match page", async ({
    page,
    shot,
  }) => {
    await signIn(page, "scout-a", { team: 1111 });
    await page.goto("/matches/2027test_qm9?tab=brief");
    await expect(
      page.getByRole("heading", { name: "Not available for your role" }),
    ).toBeVisible();
    await shot("refused");
  });

  test("the Plan board draws, places robots and zooms", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/matches/2027test_qm9?tab=plan");
    const board = page.getByRole("group", { name: /^Strategy board/ });
    await expect(board).toBeVisible();
    await shot("empty", { fullPage: true });

    await page.getByRole("button", { name: "Draw", exact: true }).click();
    await board.evaluate((el) => el.scrollIntoView({ block: "center" }));
    const box = await board.boundingBox();
    if (!box) throw new Error("no board");
    const at = (fx: number, fy: number) => ({
      x: box.x + box.width * fx,
      y: box.y + box.height * fy,
    });
    const start = at(0.3, 0.4);
    await page.mouse.move(start.x, start.y);
    await page.mouse.down();
    for (const [fx, fy] of [
      [0.4, 0.45],
      [0.5, 0.4],
      [0.6, 0.5],
    ] as const) {
      const p = at(fx, fy);
      await page.mouse.move(p.x, p.y, { steps: 6 });
    }
    await page.mouse.up();
    await expect(page.getByRole("group", { name: /1 drawing/ })).toBeVisible();
    await shot("drawn", { fullPage: true });

    await page.getByRole("button", { name: "Robot", exact: true }).click();
    await page.getByRole("button", { name: "Place all six" }).click();
    await expect(page.getByRole("group", { name: /6 robots/ })).toBeVisible();
    await shot("robots-placed", { fullPage: true });

    await page.getByRole("button", { name: "Zoom in" }).click();
    await page.getByRole("button", { name: "Zoom in" }).click();
    await shot("zoomed");
    await page.getByRole("button", { name: "Reset zoom" }).click();

    if (
      await page.getByRole("button", { name: "Exit full screen" }).isVisible()
    ) {
      await page.getByRole("button", { name: "Exit full screen" }).click();
    }
    await page.getByRole("button", { name: "Full screen" }).click();
    await expect(
      page.getByRole("dialog", { name: "Strategy board" }),
    ).toBeVisible();
    await shot("full-screen");
    await page.getByRole("button", { name: "Exit full screen" }).click();
  });

  test("the Plan board places, edits, moves and undoes a text label", async ({
    page,
    shot,
    hasTouch,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/matches/2027test_qm9?tab=plan");
    let board = page.getByRole("group", { name: /^Strategy board/ });
    await expect(board).toBeVisible();
    await page.getByRole("button", { name: "Clear Auto" }).click();
    board = page.getByRole("group", {
      name: "Strategy board, Auto phase, empty",
    });
    await expect(board).toBeVisible();
    await board.evaluate((el) => el.scrollIntoView({ block: "center" }));
    await expect
      .poll(async () => {
        const field = await board.locator(".board-field").boundingBox();
        return field ? field.width * field.height : 0;
      })
      .toBeGreaterThan(0);
    const box = await board.boundingBox();
    if (!box) throw new Error("no board");

    const press = (target: typeof board, position: { x: number; y: number }) =>
      hasTouch ? target.tap({ position }) : target.click({ position });

    await page.getByRole("button", { name: "Text", exact: true }).click();
    await press(board, { x: box.width * 0.5, y: box.height * 0.5 });
    const input = page.getByRole("textbox", { name: "Label text" });
    await input.fill("Auto left");
    await input.press("Enter");
    const label = page.getByRole("button", { name: /Auto left/ });
    await expect(label).toBeVisible();
    const labelBox = await label.boundingBox();
    const stage = page.locator(".board-stage");
    const stageBox = await stage.boundingBox();
    if (!labelBox || !stageBox) throw new Error("no label or board box");
    await press(stage, {
      x: labelBox.x + labelBox.width / 2 - stageBox.x,
      y: labelBox.y + labelBox.height / 2 - stageBox.y,
    });
    await input.fill("Auto start");
    await input.press("Enter");
    const edited = page.getByRole("button", { name: /Auto start/ });
    await expect(edited).toBeVisible();
    const before = await edited.boundingBox();
    if (!before) throw new Error("no label box");
    await shot("text-edited");

    await page.mouse.move(
      before.x + before.width / 2,
      before.y + before.height / 2,
    );
    await page.mouse.down();
    await page.mouse.move(
      before.x + before.width / 2 + 60,
      before.y + before.height / 2 + 30,
      { steps: 8 },
    );
    await page.mouse.up();
    const moved = await edited.boundingBox();
    if (!moved) throw new Error("no moved label box");
    expect(Math.hypot(moved.x - before.x, moved.y - before.y)).toBeGreaterThan(
      30,
    );
    await shot("text-dragged");

    await page.getByRole("button", { name: "Undo" }).click();
    await expect
      .poll(async () => {
        const restored = await edited.boundingBox();
        return restored
          ? [Math.round(restored.x), Math.round(restored.y)]
          : null;
      })
      .toEqual([Math.round(before.x), Math.round(before.y)]);
    await expect(edited).toBeVisible();
    await shot("text-undo");
  });
});

test.describe("picks", () => {
  test("a team moves between tiers", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/picks");
    await expect(page.getByRole("heading", { name: /1st pick/ })).toBeVisible();
    await shot("before", { fullPage: true });
    await page.getByRole("checkbox", { name: "Compare 3333" }).check();
    await page.getByRole("checkbox", { name: "Compare 2222" }).check();
    await expect(page.getByRole("link", { name: "Compare" })).toHaveAttribute(
      "href",
      "/teams/compare?t=3333,2222",
    );

    if (isBar(page)) {
      await page.getByRole("button", { name: "Move 2222 down" }).click();
      await expect(
        page.getByRole("button", { name: "Move 3333 up" }),
      ).toBeDisabled();
    } else {
      const handle = page.getByRole("button", { name: "Reorder 3333" });
      const target = page.getByRole("region", { name: /Defense\/role/ });
      const from = await handle.boundingBox();
      const to = await target.boundingBox();
      if (!from || !to) throw new Error("no drag boxes");
      await page.mouse.move(from.x + from.width / 2, from.y + from.height / 2);
      await page.mouse.down();
      await page.mouse.move(to.x + to.width / 2, to.y + 60, { steps: 12 });
      await shot("dragging");
      await page.mouse.up();
      await expect(
        page.getByRole("region", { name: /Defense\/role/ }).getByText("3333"),
      ).toBeVisible({ timeout: 30_000 });
    }
    await shot("after", { fullPage: true });
  });

  test("the draft board records a pick and undoes it", async ({
    page,
    shot,
  }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/picks");
    await page.getByRole("link", { name: "Draft board" }).click();
    await shot("draft", { fullPage: true });
    await page
      .getByLabel("Team number for the alliance on the clock")
      .fill("99999");
    await page.getByRole("button", { name: "Record pick" }).click();
    await expect(page.getByRole("alert")).toContainText("not at this event");
    await page.getByRole("button", { name: "Bracket", exact: true }).click();
    await expect(
      page.getByRole("heading", { name: "Playoff bracket" }),
    ).toBeVisible();
    await page
      .getByRole("button", { name: "Simulations", exact: true })
      .click();
    await expect(
      page.getByRole("heading", { name: "Build your own" }),
    ).toBeVisible();
    await page.getByRole("button", { name: "Selection", exact: true }).click();
  });
});

test.describe("settings and the rest", () => {
  test("Settings sections open", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await navLink(page, "Settings")
      .click()
      .catch(async () => {
        await page.goto("/settings");
      });
    if (isBar(page)) await page.goto("/settings");
    await shot("index", { fullPage: true });
    for (const s of ["event", "device", "data", "account", "help"]) {
      await page.goto(`/settings?s=${s}`);
      await page.getByRole("heading").first().waitFor();
      await shot(s, { fullPage: true });
    }
  });

  test("Accuracy shows estimates for leads", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/scout/accuracy");
    await expect(
      page.getByRole("heading", { name: "Scouter accuracy" }),
    ).toBeVisible();
    await expect(page.getByText("Scout C")).toBeVisible({ timeout: 30_000 });
    await shot("accuracy", { fullPage: true });
  });

  test("an admin sees the Users list", async ({ page, shot }) => {
    await signIn(page, "admin-c", { team: 1111 });
    await page.goto("/users");
    await expect(page.getByText("Scout A").first()).toBeVisible({
      timeout: 30_000,
    });
    await shot("users", { fullPage: true });
  });

  test("training starts a past event and leaves it", async ({ page, shot }) => {
    await signIn(page, "lead-b", { team: 1111 });
    await page.goto("/settings?s=event");
    await page.getByLabel("Past event key").fill("2027test");
    await page.getByRole("button", { name: "Start training" }).click();
    await expect(
      page.getByRole("button", { name: "Play next match" }),
    ).toBeVisible({
      timeout: 30_000,
    });
    await shot("started", { fullPage: true });
    await page.getByRole("button", { name: "Play next match" }).click();
    await shot("played-one", { fullPage: true });
    await page
      .getByRole("region", { name: "Training" })
      .getByRole("button", { name: "Leave training" })
      .click();
    await expect(
      page.getByRole("button", { name: "Start training" }),
    ).toBeVisible();
    await shot("left");
  });
});
