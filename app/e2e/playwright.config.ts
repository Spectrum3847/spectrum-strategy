import { defineConfig, devices } from "@playwright/test";

const port = 4173;
const out = process.env.E2E_OUT ?? "out";
const device = process.env.E2E_DEVICE ?? "run";

export default defineConfig({
  testDir: "specs",
  outputDir: `${out}/artifacts-${device}`,
  workers: 1,
  fullyParallel: false,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 20_000 },
  reporter: [
    ["list"],
    ["json", { outputFile: `${out}/report-${device}.json` }],
  ],
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    trace: "retain-on-failure",
    actionTimeout: 15_000,
  },
  projects: [
    {
      name: "ipad",
      use: { ...devices["iPad Pro 11"], serviceWorkers: "block" },
    },
    {
      name: "iphone",
      use: { ...devices["iPhone 15"], serviceWorkers: "block" },
    },
    { name: "pixel", use: { ...devices["Pixel 7"] } },
    {
      name: "laptop",
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1440, height: 900 },
      },
    },
  ],
  webServer: {
    command: `pnpm exec vite preview --outDir dist-e2e --host 127.0.0.1 --port ${port} --strictPort`,
    cwd: "..",
    url: `http://127.0.0.1:${port}`,
    reuseExistingServer: false,
  },
});
