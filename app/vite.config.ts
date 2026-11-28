import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import react from "@vitejs/plugin-react";
import { loadEnv } from "vite";
import { VitePWA } from "vite-plugin-pwa";
import { defineConfig } from "vitest/config";
import { emulatorFlag } from "./vite.emulators.ts";

const pkg = JSON.parse(readFileSync("package.json", "utf8")) as {
  version: string;
};

function gitSha(): string {
  try {
    return execSync("git rev-parse --short HEAD", { stdio: "pipe" })
      .toString()
      .trim();
  } catch {
    return "unknown";
  }
}

export default defineConfig(({ mode }) => ({
  define: {
    "import.meta.env.VITE_FIREBASE_EMULATORS": JSON.stringify(
      emulatorFlag(mode, loadEnv(mode, process.cwd()).VITE_FIREBASE_EMULATORS),
    ),
    __APP_VERSION__: JSON.stringify(pkg.version),
    __BUILD_SHA__: JSON.stringify(gitSha()),
    __BUILD_TIME__: JSON.stringify(new Date().toISOString()),
  },
  plugins: [
    react(),
    VitePWA({
      registerType: "prompt",
      includeAssets: ["icons/*.png"],
      workbox: {
        globPatterns: ["**/*.{js,css,html,woff2,png,webp,svg,wasm}"],
        navigateFallback: "index.html",
        navigateFallbackDenylist: [/^\/__\//],
        cleanupOutdatedCaches: true,
        importScripts: ["push-sw.js", "clear-flutter-caches-sw.js"],
      },
      manifest: {
        id: "/",
        name: "Spectrum Strategy",
        short_name: "Strategy",
        description: "FRC strategy, scouting and prematch analysis.",
        start_url: "/",
        scope: "/",
        display: "standalone",
        orientation: "any",
        theme_color: "#3C0060",
        background_color: "#F6F4F9",
        icons: [
          { src: "/icons/Icon-192.png", sizes: "192x192", type: "image/png" },
          { src: "/icons/Icon-512.png", sizes: "512x512", type: "image/png" },
          {
            src: "/icons/Icon-maskable-192.png",
            sizes: "192x192",
            type: "image/png",
            purpose: "maskable",
          },
          {
            src: "/icons/Icon-maskable-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
    }),
  ],
  server: { fs: { allow: [".."] } },
  test: {
    include: ["src/**/*.test.{ts,tsx}"],
    environment: "node",
    pool: "threads",
    setupFiles: ["src/testSetup.ts"],
  },
}));
