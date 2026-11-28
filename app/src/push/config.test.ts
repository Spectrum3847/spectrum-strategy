import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { vapidPublicKey } from "./config";

describe("vapidPublicKey", () => {
  it("is the key the Worker signs with", () => {
    const wrangler = readFileSync(
      new URL("../../../scripts/cron-worker/wrangler.jsonc", import.meta.url),
      "utf8",
    );
    expect(wrangler).toContain(`"VAPID_PUBLIC_KEY": "${vapidPublicKey}"`);
  });
});
