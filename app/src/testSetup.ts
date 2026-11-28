import { afterEach } from "vitest";

const marker = "React Router caught the following error";
let caught: string | null = null;

for (const level of ["error", "warn"] as const) {
  const original = console[level];
  console[level] = (...args: unknown[]) => {
    const text = args.map(String).join(" ");
    if (caught === null && text.includes(marker)) caught = text.slice(0, 400);
    original(...args);
  };
}

afterEach(() => {
  const found = caught;
  caught = null;
  if (found !== null) {
    throw new Error(`A page crashed into the router's error screen: ${found}`);
  }
});
