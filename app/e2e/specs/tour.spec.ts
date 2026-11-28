import { signIn, test } from "../support.ts";

const paths = [
  "/",
  "/scout",
  "/scout/pit",
  "/scout/prescout",
  "/scout/trex",
  "/scout/trex/reports",
  "/scout/shifts",
  "/scout/accuracy",
  "/schedule",
  "/teams",
  "/teams/compare",
  "/teams/2222",
  "/matches/2027test_qm9",
  "/picks",
  "/picks/playoffs",
  "/settings",
  "/users",
];

test("screen tour as admin", async ({ page, shot }) => {
  await signIn(page, "admin-c", { team: 1111 });
  for (const path of paths) {
    await page.goto(path);
    await page.getByRole("heading").first().waitFor();
    await page.waitForTimeout(1500);
    await shot(path === "/" ? "now" : path.slice(1).replace(/\//g, "-"), {
      fullPage: true,
    });
  }
});
