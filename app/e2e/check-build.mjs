import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const markers = ["demo-spectrum-e2e", "19099", "Test sign-in"];
const [dir, expectation] = process.argv.slice(2);
if (!dir || !["absent", "present"].includes(expectation ?? "")) {
  throw new Error("Usage: node check-build.mjs <dist dir> <absent|present>");
}

function* files(root) {
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) yield* files(path);
    else if (/\.(js|css|html|map|webmanifest)$/.test(entry.name)) yield path;
  }
}

const text = [...files(dir)].map((f) => readFileSync(f, "utf8")).join("\n");
const found = markers.filter((m) => text.includes(m));
const ok =
  expectation === "absent"
    ? found.length === 0
    : found.length === markers.length;
console.log(`${dir}: emulator markers found: ${found.join(", ") || "none"}`);
if (!ok) {
  console.error(`Expected the markers to be ${expectation} in ${dir}.`);
  process.exit(1);
}
